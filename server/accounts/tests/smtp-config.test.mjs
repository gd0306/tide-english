import test from "node:test";
import assert from "node:assert/strict";
import tls from "node:tls";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig } from "../src/config.mjs";
import { SMTPMailer } from "../src/smtp.mjs";
const valid = {
  DATABASE_URL: "postgresql://runtime:synthetic@localhost/accounts",
  OTP_PEPPER: "synthetic-test-pepper-32-bytes-long",
  SMTP_HOST: "localhost",
  SMTP_PORT: "465",
  SMTP_SECURE: "true",
  SMTP_USER: "sender@example.com",
  SMTP_PASSWORD: "synthetic-smtp-password",
  SMTP_FROM: "sender@example.com",
  PUBLIC_ORIGIN: "https://api.example.com",
};
test("configuration validates all required values, origins, TLS and loopback binding", () => {
  const c = loadConfig(valid);
  assert.equal(c.host, "127.0.0.1");
  assert.equal(c.port, 8189);
  assert.equal(c.smtp.secure, true);
  assert.equal(c.smtp.requireTLS, true);
  for (const override of [
    { OTP_PEPPER: "short" },
    { SMTP_PASSWORD: "" },
    { SMTP_SECURE: "maybe" },
    { SMTP_PORT: "0" },
    { PUBLIC_ORIGIN: "https://user:pass@api.example.com" },
    { PUBLIC_ORIGIN: "https://api.example.com/path" },
    { PUBLIC_ORIGIN: "https://api.example.com?q=1" },
    { ACCOUNTS_HOST: "0.0.0.0" },
    { SMTP_FROM: "A <a@example.com>" },
    { DATABASE_URL: "http://localhost/db" },
  ])
    assert.throws(() => loadConfig({ ...valid, ...override }));
  assert.throws(() => loadConfig({}));
  assert.equal(
    loadConfig({ ...valid, SMTP_SECURE: "false", SMTP_PORT: "587" }).smtp
      .requireTLS,
    true,
  );
});
test("SMTP verification and code delivery use authenticated TLS fixture without attachment/URL content", async () => {
  const dir = mkdtempSync(join(tmpdir(), "accounts-smtp-test-"));
  let server, mailer;
  try {
    execFileSync(
      "openssl",
      [
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        join(dir, "key.pem"),
        "-out",
        join(dir, "cert.pem"),
        "-days",
        "1",
        "-subj",
        "/CN=localhost",
        "-addext",
        "subjectAltName=DNS:localhost",
      ],
      { stdio: "ignore" },
    );
    const cert = readFileSync(join(dir, "cert.pem"));
    const messages = [];
    let authenticated = 0;
    server = tls.createServer(
      { key: readFileSync(join(dir, "key.pem")), cert },
      (socket) => {
        socket.write("220 localhost test SMTP\r\n");
        let buffer = "",
          inData = false,
          data = "";
        socket.on("data", (chunk) => {
          buffer += chunk;
          while (buffer.includes("\r\n")) {
            const at = buffer.indexOf("\r\n");
            const line = buffer.slice(0, at);
            buffer = buffer.slice(at + 2);
            if (inData) {
              if (line === ".") {
                messages.push(data);
                data = "";
                inData = false;
                socket.write("250 queued\r\n");
              } else data += line + "\r\n";
              continue;
            }
            if (line.startsWith("EHLO"))
              socket.write("250-localhost\r\n250 AUTH PLAIN\r\n");
            else if (line.startsWith("AUTH PLAIN")) {
              authenticated++;
              socket.write("235 authenticated\r\n");
            } else if (
              line.startsWith("MAIL FROM") ||
              line.startsWith("RCPT TO")
            )
              socket.write("250 accepted\r\n");
            else if (line === "DATA") {
              inData = true;
              socket.write("354 send data\r\n");
            } else if (line === "QUIT") {
              socket.end("221 bye\r\n");
            } else socket.write("250 ok\r\n");
          }
        });
      },
    );
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    mailer = new SMTPMailer({
      host: "localhost",
      port: server.address().port,
      secure: true,
      user: "sender@example.com",
      password: "synthetic-smtp-password",
      from: "sender@example.com",
      ca: cert,
    });
    assert.equal(mailer.transport.options.logger, false);
    assert.equal(mailer.transport.options.debug, false);
    assert.equal(mailer.transport.options.disableFileAccess, true);
    assert.equal(mailer.transport.options.disableUrlAccess, true);
    assert.equal(mailer.transport.options.tls.rejectUnauthorized, true);
    assert.equal(mailer.transport.options.requireTLS, true);
    assert.equal(await mailer.verify(), true);
    await mailer.sendCode("learner@example.com", "123456");
    await mailer.sendTest("owner@example.com");
    assert.equal(messages.length, 2);
    assert.ok(messages[0].includes("123456"));
    assert.ok(messages[0].includes("learner@example.com"));
    assert.equal(authenticated, 3);
    await assert.rejects(() =>
      mailer.sendCode("victim@example.com\r\nBcc: bad@example.com", "123456"),
    );
    await assert.rejects(() =>
      mailer.sendCode("learner@example.com", "notcode"),
    );
    const untrusted = new SMTPMailer({
      host: "localhost",
      port: server.address().port,
      secure: true,
      user: "sender@example.com",
      password: "synthetic",
      from: "sender@example.com",
    });
    await assert.rejects(() => untrusted.verify());
    untrusted.close();
  } finally {
    mailer?.close();
    if (server) await new Promise((resolve) => server.close(resolve));
    rmSync(dir, { recursive: true, force: true });
  }
});
