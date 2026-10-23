// Explicit Docker-only smoke check; production images do not copy test files.
import assert from "node:assert/strict";
import tls from "node:tls";
import { readFile } from "node:fs/promises";
import { startAccounts } from "/app/src/main.mjs";
import { loadConfig } from "/app/src/config.mjs";
if (
  !process.env.DATABASE_URL ||
  !new URL(process.env.DATABASE_URL).pathname.endsWith("_test")
)
  throw new Error("Container smoke requires an explicit _test database");
assert.equal(process.getuid(), 1000);
const cert = await readFile("/fixture/cert.pem");
const messages = [];
const fixture = tls.createServer(
  { key: await readFile("/fixture/key.pem"), cert },
  (socket) => {
    socket.write("220 localhost test SMTP\r\n");
    let buffer = "",
      body = "",
      inData = false;
    socket.on("data", (chunk) => {
      buffer += chunk;
      while (buffer.includes("\r\n")) {
        const offset = buffer.indexOf("\r\n"),
          line = buffer.slice(0, offset);
        buffer = buffer.slice(offset + 2);
        if (inData) {
          if (line === ".") {
            messages.push(body);
            body = "";
            inData = false;
            socket.write("250 queued\r\n");
          } else body += line + "\r\n";
          continue;
        }
        if (line.startsWith("EHLO"))
          socket.write("250-localhost\r\n250 AUTH PLAIN\r\n");
        else if (line.startsWith("AUTH PLAIN"))
          socket.write("235 authenticated\r\n");
        else if (line === "DATA") {
          inData = true;
          socket.write("354 send data\r\n");
        } else if (line === "QUIT") socket.end("221 bye\r\n");
        else socket.write("250 ok\r\n");
      }
    });
  },
);
await new Promise((resolve) => fixture.listen(0, "127.0.0.1", resolve));
let service;
try {
  const config = loadConfig({
    ...process.env,
    OTP_PEPPER: "synthetic-test-pepper-32-bytes-long",
    PUBLIC_ORIGIN: "https://api.example.com",
    SMTP_HOST: "localhost",
    SMTP_PORT: String(fixture.address().port),
    SMTP_SECURE: "true",
    SMTP_USER: "sender@example.com",
    SMTP_PASSWORD: "synthetic-fixture-only",
    SMTP_FROM: "sender@example.com",
    SOURCE_REVISION: "task-1-container-smoke",
    ACCOUNTS_TRUST_PROXY: "false",
  });
  config.smtp.ca = cert;
  service = await startAccounts(config);
  const health = await fetch("http://127.0.0.1:8189/healthz");
  assert.equal(health.status, 200);
  assert.equal(health.headers.get("cache-control"), "no-store");
  assert.equal((await health.json()).revision, "task-1-container-smoke");
  assert.equal((await fetch("http://127.0.0.1:8189/readyz")).status, 200);
  const post = (path, payload) =>
    fetch(`http://127.0.0.1:8189${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
  const challenge = await post("/v1/email-auth/challenge", {
    email: "container@example.com",
  });
  assert.equal(challenge.status, 202);
  const c = await challenge.json();
  assert.equal(messages.length, 1);
  const code = messages[0].match(/code is (\d{6})/)[1];
  const verified = await post("/v1/email-auth/verify", {
    challengeID: c.challengeID,
    code,
  });
  assert.equal(verified.status, 200);
  const session = await verified.json();
  assert.equal(session.email, "container@example.com");
  const profile = await fetch("http://127.0.0.1:8189/v1/email-account", {
    headers: { authorization: `Bearer ${session.accessToken}` },
  });
  assert.equal(profile.status, 200);
  assert.equal((await profile.json()).accountID, session.accountID);
  assert.equal(
    (
      await post("/v1/email-auth/sign-out", {
        refreshToken: session.refreshToken,
      })
    ).status,
    200,
  );
  await service.shutdown();
  await service.shutdown();
  service = null;
  process.stdout.write(
    "Container smoke passed: non-root, read-only, real HTTP health/readiness/login/profile/sign-out, PostgreSQL runtime role, authenticated TLS fixture, idempotent shutdown\n",
  );
} finally {
  await service?.shutdown();
  await new Promise((resolve) => fixture.close(resolve));
}
