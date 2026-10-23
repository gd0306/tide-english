import nodemailer from "nodemailer";
import { normalizeEmail, validCode } from "./accounts.mjs";
export class SMTPMailer {
  constructor({ host, port, secure = true, user, password, from, ca }) {
    if (!normalizeEmail(from)) throw new Error("Invalid SMTP sender");
    this.from = normalizeEmail(from);
    this.transport = nodemailer.createTransport({
      host,
      port,
      secure,
      requireTLS: true,
      auth: { user, pass: password },
      logger: false,
      debug: false,
      disableFileAccess: true,
      disableUrlAccess: true,
      tls: { rejectUnauthorized: true, ...(ca ? { ca } : {}) },
      connectionTimeout: 10000,
      greetingTimeout: 10000,
      socketTimeout: 15000,
    });
  }
  verify() {
    return this.transport.verify();
  }
  async sendCode(email, code) {
    if (!validCode(code)) throw new Error("Invalid code");
    return this.send(
      email,
      "Your Tide English code",
      `Your Tide English sign-in code is ${code}. It expires in 5 minutes. If you did not request this code, you can ignore this email.`,
    );
  }
  async sendTest(email) {
    return this.send(
      email,
      "Tide English email delivery check",
      "Tide English account email delivery is configured. This message contains no login code.",
    );
  }
  async send(email, subject, text) {
    const normalized = normalizeEmail(email);
    if (!normalized) throw new Error("Invalid recipient");
    return this.transport.sendMail({
      from: this.from,
      to: normalized,
      subject,
      text,
      disableFileAccess: true,
      disableUrlAccess: true,
    });
  }
  close() {
    this.transport.close();
  }
}
