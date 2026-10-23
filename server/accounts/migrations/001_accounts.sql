CREATE TABLE IF NOT EXISTS email_accounts (
 id uuid PRIMARY KEY, email varchar(254) NOT NULL UNIQUE, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS email_challenges (
 id uuid PRIMARY KEY, email varchar(254) NOT NULL, code_hash char(64) NOT NULL,
 attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
 state text NOT NULL CHECK (state IN ('pending','delivered','failed','used')),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS email_challenges_email ON email_challenges(email);
CREATE INDEX IF NOT EXISTS email_challenges_expiry ON email_challenges(expires_at);
CREATE TABLE IF NOT EXISTS email_families (
 id uuid PRIMARY KEY, account_id uuid NOT NULL REFERENCES email_accounts(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL, revoked boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS email_families_account ON email_families(account_id);
CREATE INDEX IF NOT EXISTS email_families_expiry ON email_families(expires_at);
CREATE TABLE IF NOT EXISTS email_tokens (
 refresh_hash char(64) PRIMARY KEY, access_hash char(64) NOT NULL UNIQUE,
 family_id uuid NOT NULL REFERENCES email_families(id) ON DELETE CASCADE,
 access_expires_at timestamptz NOT NULL, rotated boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS email_tokens_family ON email_tokens(family_id);
CREATE TABLE IF NOT EXISTS email_admissions (
 scope text NOT NULL CHECK (scope IN ('mailbox','send_ip','service','request_ip')),
 key text NOT NULL, admitted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS email_admissions_lookup ON email_admissions(scope,key,admitted_at);
CREATE INDEX IF NOT EXISTS email_admissions_expiry ON email_admissions(admitted_at);
