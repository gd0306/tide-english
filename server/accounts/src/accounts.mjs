import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  randomUUID,
  timingSafeEqual,
} from "node:crypto";
export const ACCESS_SECONDS = 900,
  REFRESH_SECONDS = 30 * 24 * 60 * 60;
export function normalizeEmail(value) {
  if (
    typeof value !== "string" ||
    /[\r\n]/.test(value) ||
    !/^[\x20-\x7e]*$/.test(value)
  )
    return null;
  const email = value.trim().toLowerCase();
  if (Buffer.byteLength(email) > 254) return null;
  const parts = email.split("@");
  if (parts.length !== 2 || !parts[0] || parts[0].length > 64) return null;
  if (
    !/^[a-z0-9!#$%&'*+\-/=?^_`{|}~]+(?:\.[a-z0-9!#$%&'*+\-/=?^_`{|}~]+)*$/.test(
      parts[0],
    )
  )
    return null;
  const labels = parts[1].split(".");
  if (
    labels.length < 2 ||
    labels.some((l) => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(l))
  )
    return null;
  return email;
}
export const validUUID = (value) =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value,
  );
export const validToken = (value) =>
  typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value);
export const validCode = (value) =>
  typeof value === "string" && /^\d{6}$/.test(value);
const hash = (value) => createHash("sha256").update(value).digest("hex");
const codeHash = (pepper, id, email, code) =>
  createHmac("sha256", pepper).update(`${id}\0${email}\0${code}`).digest("hex");
const failure = (status, code) => ({ status, error: code });
// The low-volume service serializes its short database mutations globally. Mail delivery
// runs outside this lock; pending challenges cannot be verified before delivery succeeds.
async function transaction(pool, work) {
  const db = await pool.connect();
  try {
    await db.query("BEGIN");
    await db.query("SELECT pg_advisory_xact_lock(8189)");
    const result = await work(db);
    await db.query("COMMIT");
    return result;
  } catch (error) {
    await db.query("ROLLBACK");
    throw error;
  } finally {
    db.release();
  }
}
async function admit(db, scope, key, limit, seconds, cooldown = 0) {
  const {
    rows: [row],
  } = await db.query(
    "SELECT count(*)::int AS count, COALESCE(bool_or(admitted_at>clock_timestamp()-($4*interval '1 second')),false) AS cooling FROM email_admissions WHERE scope=$1 AND key=$2 AND admitted_at>clock_timestamp()-($3*interval '1 second')",
    [scope, key, seconds, cooldown],
  );
  return row.count < limit && !row.cooling;
}
async function record(db, scope, key) {
  await db.query(
    "INSERT INTO email_admissions(scope,key,admitted_at) VALUES($1,$2,clock_timestamp())",
    [scope, key],
  );
}
async function session(db, account, family = null) {
  if (!family) {
    const { rows } = await db.query(
      "INSERT INTO email_families(id,account_id,expires_at) VALUES($1,$2,clock_timestamp()+interval '30 days') RETURNING *",
      [randomUUID(), account.id],
    );
    family = rows[0];
  }
  const accessToken = randomBytes(32).toString("base64url"),
    refreshToken = randomBytes(32).toString("base64url");
  await db.query(
    "INSERT INTO email_tokens(refresh_hash,access_hash,family_id,access_expires_at) VALUES($1,$2,$3,clock_timestamp()+interval '900 seconds')",
    [hash(refreshToken), hash(accessToken), family.id],
  );
  const {
    rows: [ttl],
  } = await db.query(
    "SELECT GREATEST(0,ceil(extract(epoch FROM ($1::timestamptz-clock_timestamp()))))::int AS seconds",
    [family.expires_at],
  );
  return {
    accountID: account.id,
    email: account.email,
    accessToken,
    expiresInSeconds: ACCESS_SECONDS,
    refreshToken,
    refreshExpiresInSeconds: ttl.seconds,
  };
}
async function access(db, token) {
  if (!validToken(token)) return null;
  const { rows } = await db.query(
    "SELECT a.* FROM email_tokens t JOIN email_families f ON f.id=t.family_id JOIN email_accounts a ON a.id=f.account_id WHERE t.access_hash=$1 AND NOT t.rotated AND NOT f.revoked AND t.access_expires_at>clock_timestamp() AND f.expires_at>clock_timestamp()",
    [hash(token)],
  );
  return rows[0] || null;
}
async function consume(db, id, code, pepper, email = null) {
  const {
    rows: [c],
  } = await db.query(
    "SELECT *, expires_at>clock_timestamp() AS fresh FROM email_challenges WHERE id=$1 FOR UPDATE",
    [id],
  );
  if (
    !c ||
    c.state !== "delivered" ||
    c.attempts >= 5 ||
    !c.fresh ||
    (email && c.email !== email)
  )
    return null;
  const expected = Buffer.from(c.code_hash, "hex"),
    actual = Buffer.from(codeHash(pepper, c.id, c.email, code), "hex");
  if (!timingSafeEqual(expected, actual)) {
    await db.query(
      "UPDATE email_challenges SET attempts=attempts+1 WHERE id=$1",
      [id],
    );
    return null;
  }
  await db.query("UPDATE email_challenges SET state='used' WHERE id=$1", [id]);
  return c;
}
export function createAccounts({ pool, mailer, otpPepper }) {
  return {
    async admitRequest(ip) {
      return transaction(pool, async (db) => {
        if (!(await admit(db, "request_ip", ip, 120, 60))) return false;
        await record(db, "request_ip", ip);
        return true;
      });
    },
    async challenge(email, ip) {
      const code = String(randomInt(0, 1000000)).padStart(6, "0"),
        id = randomUUID();
      const accepted = await transaction(pool, async (db) => {
        if (
          !(await admit(db, "mailbox", email, 6, 3600, 60)) ||
          !(await admit(db, "send_ip", ip, 30, 3600)) ||
          !(await admit(db, "service", "all", 200, 86400))
        )
          return false;
        await record(db, "mailbox", email);
        await record(db, "send_ip", ip);
        await record(db, "service", "all");
        await db.query("DELETE FROM email_challenges WHERE email=$1", [email]);
        await db.query(
          "INSERT INTO email_challenges(id,email,code_hash,state,expires_at) VALUES($1,$2,$3,'pending',clock_timestamp()+interval '300 seconds')",
          [id, email, codeHash(otpPepper, id, email, code)],
        );
        return true;
      });
      if (!accepted) return failure(429, "rate_limited");
      try {
        await mailer.sendCode(email, code);
        const r = await pool.query(
          "UPDATE email_challenges SET state='delivered' WHERE id=$1 AND state='pending' AND expires_at>clock_timestamp()",
          [id],
        );
        if (r.rowCount !== 1) return failure(503, "email_delivery_unavailable");
      } catch {
        await pool.query(
          "UPDATE email_challenges SET state='failed' WHERE id=$1 AND state='pending'",
          [id],
        );
        return failure(503, "email_delivery_unavailable");
      }
      return { challengeID: id, expiresInSeconds: 300, retryAfterSeconds: 60 };
    },
    async verify(id, code) {
      return transaction(pool, async (db) => {
        const c = await consume(db, id, code, otpPepper);
        if (!c) return failure(401, "invalid_code");
        const {
          rows: [a],
        } = await db.query(
          "INSERT INTO email_accounts(id,email) VALUES($1,$2) ON CONFLICT(email) DO UPDATE SET email=EXCLUDED.email RETURNING *",
          [randomUUID(), c.email],
        );
        return session(db, a);
      });
    },
    async refresh(token) {
      return transaction(pool, async (db) => {
        const {
          rows: [t],
        } = await db.query(
          "SELECT t.rotated,f.*,a.email,f.expires_at>clock_timestamp() AS fresh FROM email_tokens t JOIN email_families f ON f.id=t.family_id JOIN email_accounts a ON a.id=f.account_id WHERE t.refresh_hash=$1 FOR UPDATE OF f",
          [hash(token)],
        );
        if (!t) return failure(401, "invalid_session");
        if (t.rotated) {
          await db.query("UPDATE email_families SET revoked=true WHERE id=$1", [
            t.id,
          ]);
          return failure(401, "invalid_session");
        }
        if (t.revoked || !t.fresh) return failure(401, "invalid_session");
        await db.query(
          "UPDATE email_tokens SET rotated=true WHERE refresh_hash=$1",
          [hash(token)],
        );
        return session(db, { id: t.account_id, email: t.email }, t);
      });
    },
    async signOut(token) {
      return transaction(pool, async (db) => {
        await db.query(
          "UPDATE email_families SET revoked=true WHERE id IN (SELECT family_id FROM email_tokens WHERE refresh_hash=$1)",
          [hash(token)],
        );
        return { signedOut: true };
      });
    },
    async profile(token) {
      return transaction(pool, async (db) => {
        const a = await access(db, token);
        return a
          ? { accountID: a.id, email: a.email }
          : failure(401, "invalid_session");
      });
    },
    async delete(token, id, code) {
      return transaction(pool, async (db) => {
        const a = await access(db, token);
        if (!a) return failure(401, "invalid_session");
        if (!(await consume(db, id, code, otpPepper, a.email)))
          return failure(401, "invalid_code");
        await db.query("DELETE FROM email_challenges WHERE email=$1", [
          a.email,
        ]);
        await db.query("DELETE FROM email_accounts WHERE id=$1", [a.id]);
        return { deleted: true };
      });
    },
  };
}
export async function pruneAccounts(pool) {
  return transaction(pool, async (db) => {
    await db.query(
      "DELETE FROM email_admissions WHERE admitted_at<clock_timestamp()-interval '1 day' OR (scope='request_ip' AND admitted_at<clock_timestamp()-interval '1 minute')",
    );
    await db.query(
      "DELETE FROM email_challenges WHERE expires_at<clock_timestamp()",
    );
    await db.query(
      "DELETE FROM email_families WHERE expires_at<clock_timestamp()",
    );
  });
}
