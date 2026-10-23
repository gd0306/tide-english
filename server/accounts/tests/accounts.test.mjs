import test, { before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import pg from "pg";
const databaseURL = process.env.ACCOUNTS_TEST_DATABASE_URL;
if (!databaseURL || !new URL(databaseURL).pathname.endsWith("_test"))
  throw new Error(
    "ACCOUNTS_TEST_DATABASE_URL must explicitly name a _test database",
  );
import { createAccountsApp } from "../src/app.mjs";
import { migrateAccounts } from "../src/migrate.mjs";
const pool = new pg.Pool({ connectionString: databaseURL });
let app, sent, mailer;
before(async () => {
  await pool.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public");
  await migrateAccounts(pool);
});
beforeEach(async () => {
  if (app) await app.close();
  await pool.query(
    "DO $$ DECLARE t record; BEGIN FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP EXECUTE format('TRUNCATE TABLE %I CASCADE',t.tablename); END LOOP; END $$",
  );
  sent = [];
  mailer = { sendCode: async (email, code) => sent.push({ email, code }) };
  app = createAccountsApp({
    pool,
    mailer,
    otpPepper: "synthetic-test-pepper-32-bytes-long",
    revision: "test",
    trustProxy: false,
  });
});
after(async () => {
  await app?.close();
  await pool.end();
});
const call = (method, url, payload, token, extra = {}) =>
  app.inject({
    method,
    url,
    payload,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    ...extra,
  });
async function challenge(email = "learner@example.com", extra = {}) {
  const r = await call(
    "POST",
    "/v1/email-auth/challenge",
    { email },
    null,
    extra,
  );
  assert.equal(r.statusCode, 202);
  return { ...r.json(), code: sent.at(-1).code };
}
async function login(email) {
  const c = await challenge(email);
  const r = await call("POST", "/v1/email-auth/verify", {
    challengeID: c.challengeID,
    code: c.code,
  });
  assert.equal(r.statusCode, 200);
  return r.json();
}
const error = (r, status, code) => {
  assert.equal(r.statusCode, status);
  assert.deepEqual(r.json(), { error: { code } });
  assert.equal(r.headers["cache-control"], "no-store");
};
test("first and returning login, normalized mailbox, isolated identity and hashed secrets", async () => {
  const c = await challenge(" LEARNER@example.com ");
  assert.equal(c.expiresInSeconds, 300);
  assert.equal(c.retryAfterSeconds, 60);
  assert.equal(sent[0].email, "learner@example.com");
  assert.match(c.code, /^\d{6}$/);
  const r = await call("POST", "/v1/email-auth/verify", {
    challengeID: c.challengeID,
    code: c.code,
  });
  assert.equal(r.statusCode, 200);
  const s = r.json();
  assert.equal(s.email, "learner@example.com");
  assert.equal(s.expiresInSeconds, 900);
  assert.equal(s.refreshExpiresInSeconds, 2592000);
  assert.match(s.accessToken, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(s.accessToken, s.refreshToken);
  const profile = await call("GET", "/v1/email-account", null, s.accessToken);
  assert.deepEqual(profile.json(), { accountID: s.accountID, email: s.email });
  const rows = await pool.query("SELECT code_hash FROM email_challenges");
  assert.notEqual(rows.rows[0].code_hash, c.code);
  const tokens = await pool.query("SELECT * FROM email_tokens");
  assert.ok(!JSON.stringify(tokens.rows).includes(s.accessToken));
  assert.ok(!JSON.stringify(tokens.rows).includes(s.refreshToken));
  await pool.query(
    "UPDATE email_admissions SET admitted_at=admitted_at-interval '61 seconds'",
  );
  assert.equal((await login()).accountID, s.accountID);
  assert.notEqual((await login("other@example.com")).accountID, s.accountID);
});
test("wrong attempts commit, exhausted correct code, expired and reused code uniformly fail", async () => {
  const c = await challenge();
  for (let i = 0; i < 5; i++)
    error(
      await call("POST", "/v1/email-auth/verify", {
        challengeID: c.challengeID,
        code: c.code === "000000" ? "000001" : "000000",
      }),
      401,
      "invalid_code",
    );
  assert.equal(
    (await pool.query("SELECT attempts FROM email_challenges")).rows[0]
      .attempts,
    5,
  );
  error(
    await call("POST", "/v1/email-auth/verify", {
      challengeID: c.challengeID,
      code: c.code,
    }),
    401,
    "invalid_code",
  );
  const d = await challenge("expired@example.com");
  await pool.query(
    "UPDATE email_challenges SET expires_at=now()-interval '1 second' WHERE id=$1",
    [d.challengeID],
  );
  error(
    await call("POST", "/v1/email-auth/verify", {
      challengeID: d.challengeID,
      code: d.code,
    }),
    401,
    "invalid_code",
  );
  const e = await challenge("once@example.com");
  const rs = await Promise.all(
    [1, 2].map(() =>
      call("POST", "/v1/email-auth/verify", {
        challengeID: e.challengeID,
        code: e.code,
      }),
    ),
  );
  assert.deepEqual(rs.map((r) => r.statusCode).sort(), [200, 401]);
});
test("delivery failure invalidates code and preserves durable send cooldown", async () => {
  mailer.sendCode = async (email, code) => {
    sent.push({ email, code });
    throw new Error("private smtp credential");
  };
  const r = await call("POST", "/v1/email-auth/challenge", {
    email: "learner@example.com",
  });
  error(r, 503, "email_delivery_unavailable");
  assert.ok(!r.body.includes("private"));
  const c = (await pool.query("SELECT id FROM email_challenges")).rows[0];
  error(
    await call("POST", "/v1/email-auth/verify", {
      challengeID: c.id,
      code: sent[0].code,
    }),
    401,
    "invalid_code",
  );
  error(
    await call("POST", "/v1/email-auth/challenge", {
      email: "learner@example.com",
    }),
    429,
    "rate_limited",
  );
});
test("durable mailbox cooldown serializes concurrent sends and survives new app", async () => {
  const rs = await Promise.all(
    [1, 2, 3].map(() =>
      call("POST", "/v1/email-auth/challenge", {
        email: "learner@example.com",
      }),
    ),
  );
  assert.deepEqual(rs.map((r) => r.statusCode).sort(), [202, 429, 429]);
  assert.equal(sent.length, 1);
  await app.close();
  app = createAccountsApp({
    pool,
    mailer,
    otpPepper: "synthetic-test-pepper-32-bytes-long",
    trustProxy: false,
  });
  error(
    await call("POST", "/v1/email-auth/challenge", {
      email: "learner@example.com",
    }),
    429,
    "rate_limited",
  );
});
test("rolling mailbox, client IP and service quotas reject admission", async () => {
  for (const [scope, key, count, mailbox] of [
    ["mailbox", "quota@example.com", 6, "quota@example.com"],
    ["send_ip", "127.0.0.1", 30, "ip@example.com"],
    ["service", "all", 200, "global@example.com"],
  ]) {
    await pool.query("TRUNCATE email_admissions");
    await pool.query(
      "INSERT INTO email_admissions(scope,key,admitted_at) SELECT $1,$2,now()-interval '2 minutes' FROM generate_series(1,$3)",
      [scope, key, count],
    );
    error(
      await call("POST", "/v1/email-auth/challenge", { email: mailbox }),
      429,
      "rate_limited",
    );
  }
});
test("refresh rotation, reuse revocation, signout of old token and invalid token", async () => {
  const s = await login();
  const r = await call("POST", "/v1/email-auth/refresh", {
    refreshToken: s.refreshToken,
  });
  assert.equal(r.statusCode, 200);
  const n = r.json();
  assert.notEqual(n.refreshToken, s.refreshToken);
  error(
    await call("GET", "/v1/email-account", null, s.accessToken),
    401,
    "invalid_session",
  );
  assert.equal(
    (await call("GET", "/v1/email-account", null, n.accessToken)).statusCode,
    200,
  );
  error(
    await call("POST", "/v1/email-auth/refresh", {
      refreshToken: s.refreshToken,
    }),
    401,
    "invalid_session",
  );
  error(
    await call("GET", "/v1/email-account", null, n.accessToken),
    401,
    "invalid_session",
  );
  assert.deepEqual(
    (
      await call("POST", "/v1/email-auth/sign-out", {
        refreshToken: s.refreshToken,
      })
    ).json(),
    { signedOut: true },
  );
  error(
    await call("POST", "/v1/email-auth/refresh", {
      refreshToken: "a".repeat(43),
    }),
    401,
    "invalid_session",
  );
});
test("concurrent refresh produces at most one replacement and revokes reuse; absolute expiry applies", async () => {
  const s = await login();
  const rs = await Promise.all(
    [1, 2].map(() =>
      call("POST", "/v1/email-auth/refresh", { refreshToken: s.refreshToken }),
    ),
  );
  assert.deepEqual(rs.map((r) => r.statusCode).sort(), [200, 401]);
  const n = rs.find((r) => r.statusCode === 200).json();
  error(
    await call("GET", "/v1/email-account", null, n.accessToken),
    401,
    "invalid_session",
  );
  const e = await login("absolute@example.com");
  await pool.query(
    "UPDATE email_families SET expires_at=now()-interval '1 second'",
  );
  error(
    await call("POST", "/v1/email-auth/refresh", {
      refreshToken: e.refreshToken,
    }),
    401,
    "invalid_session",
  );
});
test("signout is idempotent and revokes rotated token family", async () => {
  const s = await login();
  const n = (
    await call("POST", "/v1/email-auth/refresh", {
      refreshToken: s.refreshToken,
    })
  ).json();
  for (let i = 0; i < 2; i++)
    assert.deepEqual(
      (
        await call("POST", "/v1/email-auth/sign-out", {
          refreshToken: s.refreshToken,
        })
      ).json(),
      { signedOut: true },
    );
  error(
    await call("GET", "/v1/email-account", null, n.accessToken),
    401,
    "invalid_session",
  );
});
test("deletion requires fresh matching code and refresh race cannot resurrect identity", async () => {
  const s = await login();
  const wrong = await challenge("other@example.com");
  error(
    await call(
      "DELETE",
      "/v1/email-account",
      { challengeID: wrong.challengeID, code: wrong.code },
      s.accessToken,
    ),
    401,
    "invalid_code",
  );
  await pool.query(
    "UPDATE email_admissions SET admitted_at=admitted_at-interval '61 seconds'",
  );
  const second = await login();
  await pool.query(
    "UPDATE email_admissions SET admitted_at=admitted_at-interval '61 seconds'",
  );
  const c = await challenge();
  const rs = await Promise.all([
    call(
      "DELETE",
      "/v1/email-account",
      { challengeID: c.challengeID, code: c.code },
      s.accessToken,
    ),
    call("POST", "/v1/email-auth/refresh", {
      refreshToken: second.refreshToken,
    }),
  ]);
  assert.ok(rs.some((r) => r.statusCode === 200));
  assert.equal(
    (await pool.query("SELECT count(*)::int AS count FROM email_accounts"))
      .rows[0].count,
    0,
  );
  assert.equal(
    (await pool.query("SELECT count(*)::int AS count FROM email_tokens"))
      .rows[0].count,
    0,
  );
  assert.equal(
    (
      await pool.query(
        "SELECT count(*)::int AS count FROM email_challenges WHERE email='learner@example.com'",
      )
    ).rows[0].count,
    0,
  );
});
test("strict inputs, bounded body, trusted IP, generic errors, disabled features and readiness", async () => {
  for (const email of [
    "a\r\nb@example.com",
    "Person <a@example.com>",
    "ü@example.com",
    "a@b",
    "a".repeat(255) + "@example.com",
  ])
    error(
      await call("POST", "/v1/email-auth/challenge", { email }),
      400,
      "invalid_request",
    );
  for (const payload of [
    { email: 4 },
    { email: "a@example.com", redirect: "https://evil.example" },
    { email: "a@example.com", extra: true },
  ])
    error(
      await call("POST", "/v1/email-auth/challenge", payload),
      400,
      "invalid_request",
    );
  error(
    await call("POST", "/v1/email-auth/challenge", { email: "a".repeat(2100) }),
    413,
    "request_too_large",
  );
  error(
    await call("GET", "/v1/email-account", null, "invalid"),
    401,
    "invalid_session",
  );
  await pool.query(
    "INSERT INTO email_admissions(scope,key) SELECT 'request_ip','127.0.0.1' FROM generate_series(1,120)",
  );
  error(
    await call("GET", "/v1/email-account", null, "a".repeat(43), {
      headers: {
        authorization: `Bearer ${"a".repeat(43)}`,
        "x-forwarded-for": "8.8.8.8",
      },
    }),
    429,
    "rate_limited",
  );
  const health = await call("GET", "/healthz");
  assert.deepEqual(health.json(), {
    ok: true,
    service: "tide-email-accounts",
    revision: "test",
    hostedVoice: false,
    livePayments: false,
    learningSync: false,
  });
  assert.equal(health.headers["cache-control"], "no-store");
  assert.equal((await call("GET", "/readyz")).statusCode, 200);
});
test("new challenge invalidates old code and pending delivery cannot authenticate", async () => {
  const old = await challenge();
  await pool.query(
    "UPDATE email_admissions SET admitted_at=admitted_at-interval '61 seconds'",
  );
  let release;
  mailer.sendCode = async (email, code) => {
    sent.push({ email, code });
    await new Promise((resolve) => {
      release = resolve;
    });
  };
  const pending = call("POST", "/v1/email-auth/challenge", {
    email: "learner@example.com",
  });
  while (!release) await new Promise((resolve) => setTimeout(resolve, 2));
  const c = (
    await pool.query(
      "SELECT id FROM email_challenges WHERE email='learner@example.com'",
    )
  ).rows[0];
  error(
    await call("POST", "/v1/email-auth/verify", {
      challengeID: c.id,
      code: sent.at(-1).code,
    }),
    401,
    "invalid_code",
  );
  error(
    await call("POST", "/v1/email-auth/verify", {
      challengeID: old.challengeID,
      code: old.code,
    }),
    401,
    "invalid_code",
  );
  release();
  assert.equal((await pending).statusCode, 202);
  assert.equal(
    (
      await call("POST", "/v1/email-auth/verify", {
        challengeID: c.id,
        code: sent.at(-1).code,
      })
    ).statusCode,
    200,
  );
});
test("proxy trust accepts configured loopback only and rejects universal trust", async () => {
  assert.throws(() =>
    createAccountsApp({
      pool,
      mailer,
      otpPepper: "synthetic-test-pepper-32-bytes-long",
      trustProxy: true,
    }),
  );
  await app.close();
  app = createAccountsApp({
    pool,
    mailer,
    otpPepper: "synthetic-test-pepper-32-bytes-long",
    trustProxy: "loopback",
  });
  await challenge("trusted@example.com", {
    remoteAddress: "127.0.0.1",
    headers: { "x-forwarded-for": "198.51.100.20" },
  });
  assert.equal(
    (await pool.query("SELECT key FROM email_admissions WHERE scope='send_ip'"))
      .rows[0].key,
    "198.51.100.20",
  );
  await challenge("untrusted@example.com", {
    remoteAddress: "198.51.100.30",
    headers: { "x-forwarded-for": "8.8.8.8" },
  });
  assert.ok(
    (
      await pool.query("SELECT key FROM email_admissions WHERE scope='send_ip'")
    ).rows.some((r) => r.key === "198.51.100.30"),
  );
});
test("expired access and expired deletion code fail; rotation preserves absolute family expiry", async () => {
  const s = await login();
  await pool.query(
    "UPDATE email_tokens SET access_expires_at=now()-interval '1 second'",
  );
  error(
    await call("GET", "/v1/email-account", null, s.accessToken),
    401,
    "invalid_session",
  );
  await pool.query(
    "UPDATE email_families SET expires_at=now()+interval '600 seconds'",
  );
  const n = (
    await call("POST", "/v1/email-auth/refresh", {
      refreshToken: s.refreshToken,
    })
  ).json();
  assert.ok(
    n.refreshExpiresInSeconds <= 600 && n.refreshExpiresInSeconds >= 599,
  );
  await pool.query(
    "UPDATE email_admissions SET admitted_at=admitted_at-interval '61 seconds'",
  );
  const c = await challenge();
  await pool.query(
    "UPDATE email_challenges SET expires_at=now()-interval '1 second'",
  );
  error(
    await call(
      "DELETE",
      "/v1/email-account",
      { challengeID: c.challengeID, code: c.code },
      n.accessToken,
    ),
    401,
    "invalid_code",
  );
  assert.equal(
    (await pool.query("SELECT count(*)::int AS count FROM email_accounts"))
      .rows[0].count,
    1,
  );
});
test("pruning removes expired challenges/families and request buckets while retaining live quotas", async () => {
  const { pruneAccounts } = await import("../src/accounts.mjs");
  await login();
  await pool.query(
    "UPDATE email_families SET expires_at=now()-interval '1 second'; UPDATE email_challenges SET expires_at=now()-interval '1 second'",
  );
  await pool.query(
    "INSERT INTO email_admissions(scope,key,admitted_at) VALUES('request_ip','old',now()-interval '61 seconds'),('mailbox','old',now()-interval '25 hours')",
  );
  await pruneAccounts(pool);
  assert.equal(
    (await pool.query("SELECT count(*)::int AS count FROM email_families"))
      .rows[0].count,
    0,
  );
  assert.equal(
    (await pool.query("SELECT count(*)::int AS count FROM email_tokens"))
      .rows[0].count,
    0,
  );
  assert.equal(
    (await pool.query("SELECT count(*)::int AS count FROM email_challenges"))
      .rows[0].count,
    0,
  );
  assert.equal(
    (
      await pool.query(
        "SELECT count(*)::int AS count FROM email_admissions WHERE key='old'",
      )
    ).rows[0].count,
    0,
  );
  assert.equal(
    (
      await pool.query(
        "SELECT count(*)::int AS count FROM email_admissions WHERE scope='mailbox'",
      )
    ).rows[0].count,
    1,
  );
});
test("database and readiness errors hide underlying secret-bearing messages", async () => {
  await app.close();
  app = createAccountsApp({
    pool: {
      connect: async () => {
        throw new Error("private db credential");
      },
      query: async () => {
        throw new Error("private db credential");
      },
    },
    mailer,
    otpPepper: "synthetic-test-pepper-32-bytes-long",
  });
  const r = await call("POST", "/v1/email-auth/challenge", {
    email: "a@example.com",
  });
  error(r, 503, "service_unavailable");
  assert.ok(!r.body.includes("private"));
  error(await call("GET", "/readyz"), 503, "service_unavailable");
});
test("runtime role can authenticate with DML grants and cannot create or drop tables", async () => {
  await pool.query(
    "DO $$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='tide_accounts_runtime_test') THEN CREATE ROLE tide_accounts_runtime_test LOGIN PASSWORD 'synthetic-runtime-only'; END IF; END $$",
  );
  await pool.query(
    "REVOKE CREATE ON SCHEMA public FROM PUBLIC; GRANT USAGE ON SCHEMA public TO tide_accounts_runtime_test; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO tide_accounts_runtime_test",
  );
  const url = new URL(databaseURL);
  url.username = "tide_accounts_runtime_test";
  url.password = "synthetic-runtime-only";
  const runtime = new pg.Pool({ connectionString: url.href });
  try {
    await assert.rejects(
      () => runtime.query("CREATE TABLE forbidden(id integer)"),
      (e) => e.code === "42501",
    );
    await assert.rejects(
      () => runtime.query("DROP TABLE email_accounts CASCADE"),
      (e) => e.code === "42501",
    );
    await app.close();
    app = createAccountsApp({
      pool: runtime,
      mailer,
      otpPepper: "synthetic-test-pepper-32-bytes-long",
      trustProxy: false,
    });
    const s = await login();
    assert.equal(
      (await call("GET", "/v1/email-account", null, s.accessToken)).statusCode,
      200,
    );
  } finally {
    await app.close();
    await runtime.end();
  }
});
test("deletion and verification compete to consume fresh code exactly once", async () => {
  const s = await login();
  await pool.query(
    "UPDATE email_admissions SET admitted_at=admitted_at-interval '61 seconds'",
  );
  const c = await challenge();
  const rs = await Promise.all([
    call(
      "DELETE",
      "/v1/email-account",
      { challengeID: c.challengeID, code: c.code },
      s.accessToken,
    ),
    call("POST", "/v1/email-auth/verify", {
      challengeID: c.challengeID,
      code: c.code,
    }),
  ]);
  assert.deepEqual(rs.map((r) => r.statusCode).sort(), [200, 401]);
  if (rs[0].statusCode === 200) {
    assert.equal(
      (await pool.query("SELECT count(*)::int AS count FROM email_accounts"))
        .rows[0].count,
      0,
    );
    error(
      await call("POST", "/v1/email-auth/verify", {
        challengeID: c.challengeID,
        code: c.code,
      }),
      401,
      "invalid_code",
    );
  } else {
    assert.equal(
      (await pool.query("SELECT count(*)::int AS count FROM email_accounts"))
        .rows[0].count,
      1,
    );
    assert.equal(rs[1].json().accountID, s.accountID);
  }
});
test("malformed URL and JSON errors remain safe and no-store", async () => {
  error(await call("GET", "/v1/%ZZ"), 400, "invalid_request");
  error(
    await call("POST", "/v1/email-auth/challenge", "{bad", null, {
      headers: { "content-type": "application/json" },
    }),
    400,
    "invalid_request",
  );
  error(await call("GET", "/missing"), 404, "not_found");
});

// Forward every query to the real PostgreSQL fixture while observing whether a
// blocked request crosses the admission boundary into account/session tables.
async function exhaustAndObserveProtectedAdmission() {
  await pool.query("DELETE FROM email_admissions WHERE scope='request_ip'");
  await pool.query(
    "INSERT INTO email_admissions(scope,key) SELECT 'request_ip','127.0.0.1' FROM generate_series(1,120)",
  );
  const queries = [];
  const observedPool = {
    query: (...args) => pool.query(...args),
    async connect() {
      const client = await pool.connect();
      return {
        query(statement, ...args) {
          queries.push(statement);
          return client.query(statement, ...args);
        },
        release: () => client.release(),
      };
    },
  };
  await app.close();
  app = createAccountsApp({
    pool: observedPool,
    mailer,
    otpPepper: "synthetic-test-pepper-32-bytes-long",
    trustProxy: false,
  });
  return queries;
}

for (const route of ["profile", "verify", "refresh", "sign-out", "delete"]) {
  test(`encoded ${route} path cannot bypass exhausted protected admission`, async () => {
    const session = await login();
    let request;
    if (route === "profile") {
      request = ["GET", "/%76%31/email-account", null, session.accessToken];
    } else if (route === "refresh" || route === "sign-out") {
      request = [
        "POST",
        `/%76%31/email-auth/${route}`,
        { refreshToken: session.refreshToken },
      ];
    } else {
      await pool.query(
        "UPDATE email_admissions SET admitted_at=admitted_at-interval '61 seconds'",
      );
      const fresh = await challenge();
      request = [
        route === "delete" ? "DELETE" : "POST",
        route === "delete"
          ? "/%76%31/email-account"
          : "/%76%31/email-auth/verify",
        { challengeID: fresh.challengeID, code: fresh.code },
        route === "delete" ? session.accessToken : null,
      ];
    }
    const queries = await exhaustAndObserveProtectedAdmission();
    error(await call(...request), 429, "rate_limited");
    assert.equal(
      queries.filter((sql) => sql.includes("FROM email_admissions")).length,
      1,
    );
    assert.equal(
      queries.some((sql) =>
        /\bemail_(accounts|families|tokens|challenges)\b/.test(sql),
      ),
      false,
      "blocked request must not execute account, OTP or token queries",
    );
    assert.equal(
      (
        await pool.query(
          "SELECT count(*)::int AS count FROM email_admissions WHERE scope='request_ip'",
        )
      ).rows[0].count,
      120,
    );
  });
}
