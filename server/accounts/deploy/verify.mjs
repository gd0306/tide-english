// Mounted read-only into the exact reviewed runtime image, never copy credentials.
import { loadConfig } from '/app/src/config.mjs';
import { SMTPMailer } from '/app/src/smtp.mjs';
import pg from '/app/node_modules/pg/lib/index.js';
const mode = process.argv[2];
try {
  const config = loadConfig();
  if (mode === 'smtp') {
    const mailer = new SMTPMailer(config.smtp);
    try {
      await mailer.verify();
      console.log('SMTP TLS and authentication passed');
      // Operator creates a durable exclusive attempt marker BEFORE invoking this.
      if (process.argv[3] === 'send-once') {
        const result = await mailer.sendTest(config.smtp.from);
        if (result.accepted?.length !== 1 || result.rejected?.length)
          throw new Error('submission failed');
        console.log('One owner test message accepted by SMTP; receipt not observed');
      }
    } finally { mailer.close(); }
  } else if (mode === 'database') {
    const pool = new pg.Pool({ connectionString: config.databaseURL, connectionTimeoutMillis: 5000 });
    try {
      const role = (await pool.query(`SELECT current_user AS name, rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls FROM pg_roles WHERE rolname=current_user`)).rows[0];
      if (role.name !== 'tide_accounts_runtime' || Object.values(role).some(v => v === true)) throw new Error();
      const permission = (await pool.query(`SELECT has_database_privilege(current_user,current_database(),'CREATE') AS db_create, has_schema_privilege(current_user,'public','CREATE') AS schema_create, has_schema_privilege(current_user,'public','USAGE') AS schema_usage`)).rows[0];
      if (permission.db_create || permission.schema_create || !permission.schema_usage) throw new Error();
      const tables = (await pool.query(`SELECT tablename,tableowner FROM pg_tables WHERE schemaname='public'`)).rows;
      if (tables.length !== 5 || tables.some(t => t.tableowner !== 'tide_accounts_owner')) throw new Error();
      for (const table of tables) {
        for (const privilege of ['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) {
          const allowed = (await pool.query('SELECT has_table_privilege(current_user,$1,$2) AS allowed',[table.tablename,privilege])).rows[0].allowed;
          if (allowed !== ['SELECT','INSERT','UPDATE','DELETE'].includes(privilege)) throw new Error();
        }
      }
      for (const statement of ['CREATE TABLE forbidden(id int)','ALTER TABLE email_accounts ADD COLUMN forbidden int','TRUNCATE email_accounts','DROP TABLE email_accounts']) {
        await pool.query('BEGIN');
        let denied = false;
        try { await pool.query(statement); } catch (error) { denied = error.code === '42501'; }
        await pool.query('ROLLBACK');
        if (!denied) throw new Error();
      }
      console.log('Runtime DML-only: five owner tables; CREATE/ALTER/TRUNCATE/DROP denied');
    } finally { await pool.end(); }
  } else throw new Error();
} catch {
  console.error('Verification failed (details suppressed to protect credentials)');
  process.exitCode = 1;
}
