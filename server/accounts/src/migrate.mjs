import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import pg from "pg";
export async function migrateAccounts(pool) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock(8188)");
    await client.query(
      await readFile(
        new URL("../migrations/001_accounts.sql", import.meta.url),
        "utf8",
      ),
    );
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const connectionString = process.env.ACCOUNTS_OWNER_DATABASE_URL;
  if (!connectionString) {
    process.stderr.write(
      "ACCOUNTS_OWNER_DATABASE_URL is required for migrations\n",
    );
    process.exitCode = 1;
  } else {
    const pool = new pg.Pool({ connectionString, max: 1 });
    try {
      await migrateAccounts(pool);
      process.stdout.write("Account migrations applied\n");
    } catch {
      process.stderr.write("Account migration failed\n");
      process.exitCode = 1;
    } finally {
      await pool.end();
    }
  }
}
