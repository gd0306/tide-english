# Tide English account deployment template

This directory contains a reproducible deployment template for the standalone email account service. No Tide English server was deployed or production-certified during this project. The existing mobile email client contract remains `https://api.gd306.cn`; using that contract does not establish that this source or image is running there.

## Local verification

Use Node 22, Docker and Python 3. Build the image from the repository root:

```sh
docker build -t tideenglish-accounts-local-verification server/accounts
docker image inspect tideenglish-accounts-local-verification --format '{{.Id}}'
```

The current locally built image is `sha256:6bd78720dd27616d51b8d581e226f8e424b8fb62fe71b8ece122212678070ad0`. Both `ops.py` and `compose.yaml` pin that immutable identity. It passed local deployment boundary tests; it is not a published or production-approved image. After changing source, rebuild, review the image and update both pins together. The helper rejects Compose overrides that resolve to another image. Do not display resolved configuration containing secrets.

Run the boundary suite from the repository root:

```sh
python3 server/accounts/deploy/test-boundaries.py
```

The five tests cover immutable image identity, Compose override rejection, durable one-shot SMTP markers, failure suppression and PostgreSQL logging boundaries. SMTP is simulated. PostgreSQL fixtures use network-disabled disposable containers and synthetic `_test` databases. No real mail or production service is required. Local verification completed with five passing tests. The full account suite also passed 25 tests against a separate disposable PostgreSQL 17 database.

For the account application tests, supply `ACCOUNTS_TEST_DATABASE_URL` through the environment with a dedicated database whose name ends in `_test`, then run `npm test` in `server/accounts`. The tests recreate that database's public schema. Never point them at retained or production data. Keep synthetic passwords out of command output and logs.

## Prepare an independent deployment

Review every domain, path, container name, port, image architecture, database role, certificate and cron entry for the intended host. The supplied Linux host-network template binds the API to `127.0.0.1:8189` and PostgreSQL to `127.0.0.1:55439`. These are template choices, not observations about an existing host. Confirm that names and ports are free; do not stop unrelated services or mount their volumes.

Use a dedicated private installation directory and separate owner/runtime database roles. Copy the required deployment files there, keep directories private, and make only the nonsecret `verify.mjs` readable by the image's nonroot user. Keep private configuration files mode 600 and out of Git. `prepare` accepts an operator-provided SMTP input file, generates missing role, OTP and backup secrets, and removes that input. Review its behavior before running it; partial configuration is rejected and existing secrets are retained.

Apply the owner-only migrations and runtime grants using the helper's `init-db` operation. Runtime must have only the required DML privileges and must not own the schema or tables. Review the pinned PostgreSQL and Certbot images against the deployment host rather than assuming local compatibility establishes production compatibility. Keep default container isolation, read-only application storage, bounded logs and the provided capability restrictions.

Configure a dedicated reverse-proxy virtual host using `nginx-acme.conf` and `nginx.conf` as examples. Preserve unrelated virtual hosts and certificates. Validate the full configuration before a graceful reload, test the ACME webroot on the selected domain, and arrange certificate renewal only after the host and domain have been authorized for this deployment. Do not assume a particular include order or default virtual host matches these templates.

Before exposing account routes, verify database ownership/grants, loopback binding, trusted proxy headers, readiness, body limits, safe errors, no-store headers and disabled hosted flags. Verify SMTP authentication separately. Real SMTP delivery and `smtp-send-once` are deliberate operator actions: the latter durably records an attempt before sending and refuses another attempt even after an uncertain result. Local fixture success does not establish mailbox delivery.

## Backups and recovery

Review the backup encryption, key storage and off-host retention policy before handling real data. Keep encrypted backups and their keys separately protected. The backup helper restores into a dedicated disposable restore-test database and produces a verification marker only after restoration checks. A local backup file alone is not a recovery plan.

For rollback, keep a reviewed prior image, source and compatible schema plan. Preserve stable OTP and database secrets. Put only the dedicated API into maintenance, take a fresh backup, and restore into a new dedicated database if required. Never overwrite retained data, delete unrelated volumes or use `docker compose down -v` as a routine rollback. Recheck readiness, runtime privileges and proxy behavior before restoring public access.

Install the example cron entry only after backup and certificate procedures have passed on the authorized target. Monitor its status files, certificate expiry and disk capacity. The helper does not automatically delete old backups. No production deployment, certificate issuance, real SMTP send or retained-data restore was performed as part of this new-engineering verification.
