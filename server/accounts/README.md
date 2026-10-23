# Tide English standalone email accounts

> New Tide English source/template only. This repository has not deployed or verified this service in production. Existing account clients retain https://api.gd306.cn. Any commercial store IDs in tests are synthetic; configure newly registered app credentials before activation.

Node 22+, PostgreSQL 17+, Fastify and Nodemailer. This service has its own database and
`email_*` tables. It does not read or write commercial accounts, learning records,
model credentials, balances or purchases. All hosted features remain disabled.

## Configuration and database setup

Copy `.env.example` to private deployment configuration outside this repository.
Generate a random OTP pepper of at least 32 bytes and keep it stable across restarts.
Changing it invalidates pending codes. Never display secrets or put them in build
arguments, shell history, committed files, logs or deployment output. The process
validates configuration, verifies database connectivity and authenticates SMTP
before listening. `PUBLIC_ORIGIN` is validated deployment metadata and is never
used as a request-controlled redirect. No endpoint redirects.

Create a dedicated `tide_accounts` database with a separate owner and runtime role.
Run migrations using **only** the owner connection:

```sh
npm ci --omit=dev --ignore-scripts
npm run migrate
```

`npm run migrate` requires `ACCOUNTS_OWNER_DATABASE_URL`; it never falls back to the
runtime connection. Keep that owner credential in separate migration-only private
configuration and do not pass it to the runtime process. Supply both role passwords privately. After migrating, apply
these grants as the owner/administrator (adjust role names if needed):

```sql
REVOKE ALL ON DATABASE tide_accounts FROM PUBLIC;
GRANT CONNECT ON DATABASE tide_accounts TO tide_accounts_runtime;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO tide_accounts_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO tide_accounts_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE tide_accounts_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tide_accounts_runtime;
```

The runtime role must not own the database/schema/tables and must have no CREATE,
ALTER, DROP, TRUNCATE, superuser or role-management privileges. Runtime migrations
are deliberately absent from startup. Owner migrations are idempotent and use a
transaction with a dedicated advisory lock.

## Running and reverse proxy

```sh
npm start
```

The service binds **127.0.0.1:8189**, configurable to another loopback port. Its
trusted proxy setting accepts only `loopback` or `false`. Nginx must connect from
loopback, overwrite `X-Forwarded-For` with `$remote_addr` (do not append incoming
forwarding headers), and proxy only this virtual host to port 8189. Keep the
existing virtual hosts untouched. Use a valid separate certificate for
`api.gd306.cn`; do not enable the client feature before the HTTPS service is ready.
Keep PostgreSQL loopback-bound on port 55439 with its dedicated volume.

Build the independent container from this directory:

```sh
docker build -t tide-email-accounts:REVISION .
```

Because the process binds loopback, **use Linux host networking** for production:
`--network host` with a private environment file, read-only root filesystem and
`--cap-drop ALL`. Publishing ports cannot reach a process listening only on a
container's loopback. The image runs as the unprivileged `node` user and has no
embedded secrets. Run migrations as a separate owner-configured invocation before
starting the runtime container. The built-in healthcheck checks `/readyz` locally.
SIGTERM/SIGINT close HTTP, SMTP and the database pool gracefully.

## Contracts and abuse limits

All responses have `Cache-Control: no-store`. JSON bodies are limited to 2048 bytes,
reject unknown fields and reject type coercion. Errors have only
`{"error":{"code":"stable_code"}}`; neither request/response bodies nor raw
SMTP/database errors are logged.

| Endpoint | Body / result |
| --- | --- |
| POST `/v1/email-auth/challenge` | `{email}` → 202 `{challengeID,expiresInSeconds:300,retryAfterSeconds:60}` |
| POST `/v1/email-auth/verify` | `{challengeID,code}` → session |
| POST `/v1/email-auth/refresh` | `{refreshToken}` → rotated session |
| POST `/v1/email-auth/sign-out` | `{refreshToken}` → `{signedOut:true}` (idempotent) |
| GET `/v1/email-account` | bearer → `{accountID,email}` |
| DELETE `/v1/email-account` | bearer + `{challengeID,code}` → `{deleted:true}` |
| GET `/healthz` | service, revision and disabled hosted feature flags |
| GET `/readyz` | 200 `{ok:true}` after PostgreSQL query; 503 safe error otherwise |

A session contains `accountID`, normalized `email`, independent random 32-byte
base64url `accessToken` and `refreshToken`, `expiresInSeconds:900` and
`refreshExpiresInSeconds` up to 2592000. Refresh lifetimes are absolute per family,
not extended by renewal. Rotating revokes the previous access token. Reusing any
rotated refresh token revokes its whole family; simultaneous refresh requests can
therefore invalidate the winning replacement. Clients must coalesce refreshes.
Sign-out also recognizes old rotated refresh tokens. Account deletion requires an
unused, delivered, unexpired code for the same email and removes all identities,
sessions and matching challenges atomically.

Only peppered challenge/email-bound HMACs and SHA-256 token hashes are persisted.
Wrong OTP attempts commit even on 401; five wrong attempts exhaust a challenge.
Expired/used/wrong codes uniformly return `invalid_code`. Delivery failures return
`email_delivery_unavailable` and preserve admission cooldown. A new accepted
challenge replaces older ones; pending delivery cannot authenticate.

Admission uses durable rolling windows: 60 seconds between mailbox sends,
6/mailbox/hour, 30/client-IP/hour, 200/service/day and 120/client-IP/minute on
verification, renewal, profile, sign-out and deletion. The low-volume backend
serializes short database mutations with a transaction-scoped advisory lock to
make quota, verification and token races safe across instances. SMTP runs outside
the transaction. Pruning runs at startup and once per minute, removing expired
challenges/families and admissions beyond their active window. Rotated token hashes
remain until family expiry to recognize reuse and historical sign-out.

Safe codes include `invalid_request` (400), `request_too_large` (413), `invalid_code`
and `invalid_session` (401), `rate_limited` (429), `email_delivery_unavailable` and
`service_unavailable` (503), and `not_found` (404).

## Local tests

Tests require an explicit `ACCOUNTS_TEST_DATABASE_URL` whose database name ends in
`_test`; missing/non-test databases fail clearly. The test suite resets the public
schema of **that test database only**. Never provide any retained or production
account/learning database. Use a separate disposable local PostgreSQL container:

```sh
docker run --name tide_accounts_test -e POSTGRES_PASSWORD=synthetic-test-only \
  -e POSTGRES_DB=tide_accounts_test -p 127.0.0.1:55449:5432 -d postgres:17-alpine
ACCOUNTS_TEST_DATABASE_URL=postgresql://postgres:synthetic-test-only@127.0.0.1:55449/tide_accounts_test npm test
npm audit --omit=dev
```

Database tests use actual transactions and concurrency, plus a DML-only test role.
SMTP tests create a disposable self-signed local CA and authenticated TLS fixture;
they verify certificate enforcement and never contact production mail services or
read owner credentials. Exported integration interfaces are
`createAccountsApp({pool,mailer,otpPepper,revision,trustProxy})`,
`migrateAccounts(pool)`, `SMTPMailer.verify/sendCode/sendTest/close`,
`pruneAccounts(pool)` and `startAccounts(config)` returning `shutdown()`.

The `tests/container-smoke.mjs` check can be mounted into the built image and run
with `node /app/container-smoke.mjs`. It requires an explicit `_test`
`DATABASE_URL`, DML-only test role, synthetic `/fixture/cert.pem` and
`/fixture/key.pem` (localhost certificate), and shares the test PostgreSQL network
namespace. It creates its own TLS mail fixture, runs real HTTP checks and verifies
unprivileged execution and idempotent shutdown.
