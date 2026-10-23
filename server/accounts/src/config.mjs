import { normalizeEmail } from "./accounts.mjs";
export function loadConfig(env = process.env) {
  const required = (name) => {
    if (typeof env[name] !== "string" || !env[name].trim())
      throw new Error(`Missing ${name}`);
    return env[name];
  };
  const integer = (name, fallback) => {
    const v = env[name] ?? String(fallback);
    if (!/^\d+$/.test(v) || Number(v) < 1 || Number(v) > 65535)
      throw new Error(`Invalid ${name}`);
    return Number(v);
  };
  const databaseURL = required("DATABASE_URL");
  let database;
  try {
    database = new URL(databaseURL);
  } catch {
    throw new Error("Invalid DATABASE_URL");
  }
  if (
    !["postgres:", "postgresql:"].includes(database.protocol) ||
    !database.hostname ||
    !database.pathname.slice(1)
  )
    throw new Error("Invalid DATABASE_URL");
  const otpPepper = required("OTP_PEPPER");
  if (Buffer.byteLength(otpPepper) < 32)
    throw new Error("OTP_PEPPER must contain at least 32 bytes");
  let origin;
  try {
    origin = new URL(required("PUBLIC_ORIGIN"));
  } catch {
    throw new Error("Invalid PUBLIC_ORIGIN");
  }
  if (
    origin.protocol !== "https:" ||
    origin.username ||
    origin.password ||
    origin.search ||
    origin.hash ||
    origin.pathname !== "/"
  )
    throw new Error("Invalid PUBLIC_ORIGIN");
  const host = env.ACCOUNTS_HOST ?? "127.0.0.1";
  if (host !== "127.0.0.1") throw new Error("ACCOUNTS_HOST must be loopback");
  const secure = env.SMTP_SECURE ?? "true";
  if (!["true", "false"].includes(secure))
    throw new Error("Invalid SMTP_SECURE");
  const smtpHost = required("SMTP_HOST");
  if (!/^[a-zA-Z0-9.-]+$/.test(smtpHost)) throw new Error("Invalid SMTP_HOST");
  const from = normalizeEmail(required("SMTP_FROM"));
  if (!from) throw new Error("Invalid SMTP_FROM");
  const trust = env.ACCOUNTS_TRUST_PROXY ?? "loopback";
  if (!["loopback", "false"].includes(trust))
    throw new Error("Invalid ACCOUNTS_TRUST_PROXY");
  return {
    databaseURL,
    otpPepper,
    publicOrigin: origin.origin,
    host,
    port: integer("ACCOUNTS_PORT", 8189),
    revision: env.SOURCE_REVISION ?? "unknown",
    trustProxy: trust === "false" ? false : "loopback",
    smtp: {
      host: smtpHost,
      port: integer("SMTP_PORT", secure === "true" ? 465 : 587),
      secure: secure === "true",
      requireTLS: true,
      user: required("SMTP_USER"),
      password: required("SMTP_PASSWORD"),
      from,
    },
  };
}
