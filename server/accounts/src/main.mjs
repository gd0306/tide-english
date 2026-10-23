import pg from "pg";
import { pathToFileURL } from "node:url";
import { loadConfig } from "./config.mjs";
import { SMTPMailer } from "./smtp.mjs";
import { createAccountsApp } from "./app.mjs";
import { pruneAccounts } from "./accounts.mjs";
export async function startAccounts(config = loadConfig()) {
  const pool = new pg.Pool({
    connectionString: config.databaseURL,
    max: 10,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
    statement_timeout: 10000,
  });
  // Never serialize database/SMTP errors: their messages may contain credentials.
  pool.on("error", () =>
    process.stderr.write("Account database connection unavailable\n"),
  );
  const mailer = new SMTPMailer(config.smtp),
    app = createAccountsApp({
      pool,
      mailer,
      otpPepper: config.otpPepper,
      revision: config.revision,
      trustProxy: config.trustProxy,
    });
  let timer, stopping;
  const shutdown = () =>
    (stopping ??= (async () => {
      clearInterval(timer);
      await app.close();
      mailer.close();
      await pool.end();
    })());
  try {
    await pool.query("SELECT 1");
    await mailer.verify();
    await pruneAccounts(pool);
    await app.listen({ host: config.host, port: config.port });
    timer = setInterval(
      () =>
        pruneAccounts(pool).catch(() =>
          process.stderr.write("Account pruning unavailable\n"),
        ),
      60000,
    );
    timer.unref();
    return { app, pool, mailer, shutdown };
  } catch (error) {
    await shutdown();
    throw error;
  }
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  try {
    const service = await startAccounts();
    for (const signal of ["SIGINT", "SIGTERM"])
      process.once(signal, () => {
        service.shutdown().catch(() => {
          process.exitCode = 1;
        });
      });
    process.stdout.write("Tide email accounts listening\n");
  } catch {
    process.stderr.write(
      "Account service startup failed: check configuration, database and SMTP\n",
    );
    process.exitCode = 1;
  }
}
