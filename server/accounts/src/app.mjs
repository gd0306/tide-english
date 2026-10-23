import Fastify from "fastify";
import {
  createAccounts,
  normalizeEmail,
  validCode,
  validToken,
  validUUID,
} from "./accounts.mjs";
export function createAccountsApp({
  pool,
  mailer,
  otpPepper,
  revision = "unknown",
  trustProxy = false,
}) {
  if (
    !pool ||
    !mailer ||
    typeof otpPepper !== "string" ||
    Buffer.byteLength(otpPepper) < 32
  )
    throw new Error("Invalid account service dependencies");
  if (trustProxy !== false && trustProxy !== "loopback")
    throw new Error("Only loopback proxy trust is permitted");
  const app = Fastify({
    logger: false,
    bodyLimit: 2048,
    frameworkErrors: (error, request, reply) =>
      reply
        .header("Cache-Control", "no-store")
        .code(400)
        .send({ error: { code: "invalid_request" } }),
    trustProxy: trustProxy === "loopback" ? ["127.0.0.1", "::1"] : false,
    ajv: {
      customOptions: {
        removeAdditional: false,
        coerceTypes: false,
        useDefaults: false,
      },
    },
  });
  const accounts = createAccounts({ pool, mailer, otpPepper });
  const fail = (reply, status, code) =>
    reply.code(status).send({ error: { code } });
  app.addHook("onRequest", async (request, reply) => {
    reply.header("Cache-Control", "no-store");
  });
  const protectedAdmission = async (request, reply) => {
    if (!(await accounts.admitRequest(request.ip)))
      return fail(reply, 429, "rate_limited");
  };
  app.setErrorHandler((error, request, reply) =>
    fail(
      reply,
      error.code === "FST_ERR_CTP_BODY_TOO_LARGE"
        ? 413
        : error.validation ||
            error.statusCode === 400 ||
            error.statusCode === 415
          ? 400
          : 503,
      error.code === "FST_ERR_CTP_BODY_TOO_LARGE"
        ? "request_too_large"
        : error.validation ||
            error.statusCode === 400 ||
            error.statusCode === 415
          ? "invalid_request"
          : "service_unavailable",
    ),
  );
  app.setNotFoundHandler((request, reply) => fail(reply, 404, "not_found"));
  const schema = (properties) => ({
    body: {
      type: "object",
      additionalProperties: false,
      required: Object.keys(properties),
      properties,
    },
  });
  const string = { type: "string" };
  const handle = (result) => async (request, reply) => {
    const r = await result(request);
    return r.error ? fail(reply, r.status, r.error) : r;
  };
  const bearer = (request) => {
    const h = request.headers.authorization;
    return typeof h === "string" && /^Bearer [A-Za-z0-9_-]{43}$/.test(h)
      ? h.slice(7)
      : null;
  };
  app.post(
    "/v1/email-auth/challenge",
    { schema: schema({ email: string }) },
    async (request, reply) => {
      const email = normalizeEmail(request.body.email);
      if (!email) return fail(reply, 400, "invalid_request");
      const r = await accounts.challenge(email, request.ip);
      return r.error ? fail(reply, r.status, r.error) : reply.code(202).send(r);
    },
  );
  const codeSchema = schema({ challengeID: string, code: string });
  app.post(
    "/v1/email-auth/verify",
    { schema: codeSchema, onRequest: protectedAdmission },
    handle((request) =>
      validUUID(request.body.challengeID) && validCode(request.body.code)
        ? accounts.verify(request.body.challengeID, request.body.code)
        : { status: 400, error: "invalid_request" },
    ),
  );
  app.post(
    "/v1/email-auth/refresh",
    { schema: schema({ refreshToken: string }), onRequest: protectedAdmission },
    handle((request) =>
      validToken(request.body.refreshToken)
        ? accounts.refresh(request.body.refreshToken)
        : { status: 401, error: "invalid_session" },
    ),
  );
  app.post(
    "/v1/email-auth/sign-out",
    { schema: schema({ refreshToken: string }), onRequest: protectedAdmission },
    handle((request) =>
      validToken(request.body.refreshToken)
        ? accounts.signOut(request.body.refreshToken)
        : { signedOut: true },
    ),
  );
  app.get(
    "/v1/email-account",
    { onRequest: protectedAdmission },
    handle((request) => accounts.profile(bearer(request))),
  );
  app.delete(
    "/v1/email-account",
    { schema: codeSchema, onRequest: protectedAdmission },
    handle((request) =>
      validUUID(request.body.challengeID) && validCode(request.body.code)
        ? accounts.delete(
            bearer(request),
            request.body.challengeID,
            request.body.code,
          )
        : { status: 400, error: "invalid_request" },
    ),
  );
  app.get("/healthz", async () => ({
    ok: true,
    service: "tide-email-accounts",
    revision,
    hostedVoice: false,
    livePayments: false,
    learningSync: false,
  }));
  app.get("/readyz", async (request, reply) => {
    try {
      await pool.query("SELECT 1");
      return { ok: true };
    } catch {
      return fail(reply, 503, "service_unavailable");
    }
  });
  return app;
}
