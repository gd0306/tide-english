#!/usr/bin/env python3
"""Root-only deployment operations. Never render environment or raw child errors."""
import argparse
import datetime
import json
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys
import time

IMAGE_ID = 'sha256:6bd78720dd27616d51b8d581e226f8e424b8fb62fe71b8ece122212678070ad0'
IMAGE = IMAGE_ID
REVISION = '83c960f'
CERTBOT = 'certbot/certbot:v5.8.0@sha256:f70ad0adbb7e117f0fe42a63c553f28ea451edabc0148757b6efcd9735acaa20'


def run(args, data=None, timeout=120):
    result = subprocess.run(args, input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout)
    if result.returncode:
        raise RuntimeError('Command failed: ' + Path(args[0]).name + ' (private output suppressed)')
    return result.stdout


def private_file(path):
    if path.is_symlink() or not path.is_file() or stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise RuntimeError('Missing or unsafe private file: ' + path.name)


def write_private(path, value):
    with os.fdopen(os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as out:
        out.write(value)
        out.flush()
        os.fsync(out.fileno())
    directory = os.open(str(path.parent), os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def compose_env(values):
    # Single-quoted dotenv values prevent Compose interpolation of SMTP '$'.
    return ''.join(k + "='" + v.replace("'", "\\'") + "'\n" for k, v in values.items())


def read_env(path):
    private_file(path)
    return dict(line.split('=', 1) for line in path.read_text().splitlines() if line and not line.startswith('#'))


def psql(sql, db='tide_accounts'):
    return run(['docker', 'exec', '-i', 'tide-accounts-db', 'psql', '-X', '-q', '-A', '-t',
                '-v', 'ON_ERROR_STOP=1', '-p', '55439', '-U', 'postgres', '-d', db], sql.encode())


def compose(root, *args):
    return run(['docker', 'compose', '--project-directory', str(root), '-f', str(root / 'compose.yaml'), *args])


def image_helper(root, *args):
    return run(['docker', 'run', '--rm', '--network', 'host', '--read-only', '--user', 'node',
                '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
                '--env-file', str(root / 'private/runtime.env'),
                '-v', str(root / 'verify.mjs') + ':/ops/verify.mjs:ro', IMAGE,
                'node', '/ops/verify.mjs', *args], timeout=90)


def prepare(root, smtp_source):
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if stat.S_IMODE(root.stat().st_mode) != 0o700:
        raise RuntimeError('Deployment directory must have mode 700')
    private = root / 'private'
    private.mkdir(mode=0o700, exist_ok=True)
    if stat.S_IMODE(private.stat().st_mode) != 0o700:
        raise RuntimeError('Private directory must have mode 700')
    names = ['postgres.env', 'owner.env', 'runtime.env', 'runtime.compose.env', 'roles.json', 'backup.key']
    existing = [(private / name).exists() for name in names]
    if any(existing):
        if not all(existing):
            raise RuntimeError('Partial private configuration: recover it; never regenerate deployed credentials')
        for name in names:
            private_file(private / name)
        print('Existing private configuration retained unchanged')
        return
    source = Path(smtp_source)
    private_file(source)
    password = source.read_text().strip()
    # Docker env files cannot represent newline; no substitution or shell interpretation.
    if not password or any(c in password for c in '\r\n\x00'):
        raise RuntimeError('Invalid private SMTP input')
    owner, runtime, admin = (secrets.token_hex(32) for _ in range(3))
    write_private(private / 'postgres.env', 'POSTGRES_PASSWORD=' + admin + '\nPOSTGRES_DB=postgres\n')
    write_private(private / 'roles.json', json.dumps({'owner': owner, 'runtime': runtime}))
    write_private(private / 'owner.env', 'ACCOUNTS_OWNER_DATABASE_URL=postgresql://tide_accounts_owner:' + owner + '@127.0.0.1:55439/tide_accounts\n')
    values = {
        'DATABASE_URL': 'postgresql://tide_accounts_runtime:' + runtime + '@127.0.0.1:55439/tide_accounts',
        'OTP_PEPPER': secrets.token_hex(48), 'PUBLIC_ORIGIN': 'https://api.gd306.cn',
        'ACCOUNTS_HOST': '127.0.0.1', 'ACCOUNTS_PORT': '8189', 'ACCOUNTS_TRUST_PROXY': 'loopback',
        'SOURCE_REVISION': REVISION, 'SMTP_HOST': 'smtp.qq.com', 'SMTP_PORT': '465',
        'SMTP_SECURE': 'true', 'SMTP_USER': '1215742191@qq.com', 'SMTP_FROM': '1215742191@qq.com',
        'SMTP_PASSWORD': password,
    }
    write_private(private / 'runtime.env', ''.join(k + '=' + v + '\n' for k, v in values.items()))
    write_private(private / 'runtime.compose.env', compose_env(values))
    write_private(private / 'backup.key', secrets.token_hex(48) + '\n')
    source.unlink()
    print('Private configuration created; SMTP input removed; no values displayed')


def check(root, certificate=False):
    if stat.S_IMODE(root.stat().st_mode) != 0o700 or stat.S_IMODE((root / 'private').stat().st_mode) != 0o700:
        raise RuntimeError('Private directories must have mode 700')
    if not (root / 'verify.mjs').is_file() or not ((root / 'verify.mjs').stat().st_mode & stat.S_IROTH):
        raise RuntimeError('Nonsecret mounted verify.mjs must be readable by the nonroot image user')
    runtime = read_env(root / 'private/runtime.env')
    private_file(root / 'private/runtime.compose.env')
    if (root / 'private/runtime.compose.env').read_text() != compose_env(runtime):
        raise RuntimeError('Compose and literal runtime configuration mismatch')
    owner = read_env(root / 'private/owner.env')
    read_env(root / 'private/postgres.env')
    for name in ['roles.json', 'backup.key']:
        private_file(root / 'private' / name)
    if 'ACCOUNTS_OWNER_DATABASE_URL' in runtime or 'DATABASE_URL' in owner:
        raise RuntimeError('Migration and runtime credentials must be separate')
    compose(root, 'config', '--quiet')
    # Parse privately: resolved Compose contains env secrets and is never printed.
    resolved_image = json.loads(compose(root, 'config', '--format', 'json'))['services']['api']['image']
    if resolved_image != IMAGE_ID:
        raise RuntimeError('Resolved Compose API image must be the reviewed immutable identity')
    actual = run(['docker', 'image', 'inspect', resolved_image, '--format', '{{.Id}}']).decode().strip()
    if actual != IMAGE_ID:
        raise RuntimeError('Reviewed runtime image identity mismatch')
    # Use the actual image configuration parser, suppress any underlying error.
    run(['docker', 'run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
         '--env-file', str(root / 'private/runtime.env'), IMAGE,
         'node', '--input-type=module', '-e', "import {loadConfig} from './src/config.mjs';loadConfig();"])
    if certificate:
        cert = root / 'letsencrypt/live/api.gd306.cn/fullchain.pem'
        key = root / 'letsencrypt/live/api.gd306.cn/privkey.pem'
        if not cert.is_file() or not key.is_file():
            raise RuntimeError('Missing TLS certificate or private key')
        run(['openssl', 'x509', '-in', str(cert), '-noout', '-checkend', '86400'])
        run(['nginx', '-t'])
    print('Private modes, configuration parser, Compose and exact image verified' + ('; TLS configuration verified' if certificate else ''))


def initialize(root):
    check(root)
    compose(root, 'up', '-d', 'db')
    for _ in range(30):
        try:
            psql('SELECT 1;', 'postgres')
            break
        except RuntimeError:
            time.sleep(2)
    else:
        raise RuntimeError('Dedicated database did not become ready')
    private_file(root / 'private/roles.json')
    roles = json.loads((root / 'private/roles.json').read_text())
    if any(not all(c in '0123456789abcdef' for c in roles[k]) or len(roles[k]) != 64 for k in ['owner', 'runtime']):
        raise RuntimeError('Invalid generated role credentials')
    # Passwords travel solely over stdin; do not pass SQL/credentials as arguments.
    for role, key in [('tide_accounts_owner', 'owner'), ('tide_accounts_runtime', 'runtime')]:
        if psql("SELECT 1 FROM pg_roles WHERE rolname='" + role + "';", 'postgres').strip() != b'1':
            psql("CREATE ROLE " + role + " LOGIN PASSWORD '" + roles[key] + "' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;", 'postgres')
    if psql("SELECT 1 FROM pg_database WHERE datname='tide_accounts';", 'postgres').strip() != b'1':
        psql('CREATE DATABASE tide_accounts OWNER tide_accounts_owner;', 'postgres')
    psql('REVOKE ALL ON DATABASE tide_accounts FROM PUBLIC; GRANT CONNECT ON DATABASE tide_accounts TO tide_accounts_runtime; REVOKE CREATE ON SCHEMA public FROM PUBLIC;')
    run(['docker', 'run', '--rm', '--network', 'host', '--read-only', '--cap-drop', 'ALL',
         '--security-opt', 'no-new-privileges:true', '--env-file', str(root / 'private/owner.env'),
         IMAGE, 'node', 'src/migrate.mjs'])
    psql('GRANT USAGE ON SCHEMA public TO tide_accounts_runtime; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO tide_accounts_runtime; ALTER DEFAULT PRIVILEGES FOR ROLE tide_accounts_owner IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO tide_accounts_runtime;')
    print(image_helper(root, 'database').decode().strip())
    print('Dedicated database and owner migrations ready')


def backup(root):
    """Encrypt directly from dump stdout, then restore into disposable dedicated test DB."""
    private_file(root / 'private/backup.key')
    directory = root / 'backups'
    directory.mkdir(mode=0o700, exist_ok=True)
    stamp = datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    target = directory / (stamp + '-' + secrets.token_hex(3) + '.dump.enc')
    fd = os.open(str(target), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    dump = subprocess.Popen(['docker', 'exec', 'tide-accounts-db', 'pg_dump', '-p', '55439', '-U', 'postgres', '-Fc', 'tide_accounts'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    with os.fdopen(fd, 'wb') as out:
        encrypted = subprocess.run(['openssl', 'enc', '-aes-256-cbc', '-pbkdf2', '-salt', '-pass', 'file:' + str(root / 'private/backup.key')], stdin=dump.stdout, stdout=out, stderr=subprocess.PIPE, timeout=120)
    dump.stdout.close()
    if dump.wait(timeout=120) or encrypted.returncode:
        raise RuntimeError('Encrypted backup failed')
    restore_db = 'tide_accounts_restore_test'
    if psql("SELECT 1 FROM pg_database WHERE datname='" + restore_db + "';", 'postgres').strip():
        raise RuntimeError('Restore test database already exists; inspect before removing')
    psql('CREATE DATABASE ' + restore_db + ' OWNER tide_accounts_owner;', 'postgres')
    try:
        decrypt = subprocess.Popen(['openssl', 'enc', '-d', '-aes-256-cbc', '-pbkdf2', '-pass', 'file:' + str(root / 'private/backup.key'), '-in', str(target)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        restore = subprocess.run(['docker', 'exec', '-i', 'tide-accounts-db', 'pg_restore', '-p', '55439', '-U', 'postgres', '-d', restore_db, '--exit-on-error'], stdin=decrypt.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        decrypt.stdout.close()
        if decrypt.wait(timeout=120) or restore.returncode:
            raise RuntimeError('Encrypted restore failed')
        query = "SELECT tablename,tableowner FROM pg_tables WHERE schemaname='public' ORDER BY tablename;"
        if psql(query) != psql(query, restore_db):
            raise RuntimeError('Recovered schema ownership mismatch')
        tables = ['email_accounts', 'email_challenges', 'email_families', 'email_tokens', 'email_admissions']
        # Live admission rows can legitimately change during online backups. Validate
        # every restored table is queryable; pg_restore checks constraints and indexes.
        for table in tables:
            psql('SELECT count(*) FROM ' + table + ';', restore_db)
    finally:
        psql('DROP DATABASE ' + restore_db + ';', 'postgres')
    write_private(Path(str(target) + '.verified'), 'Decrypted and pg_restore --exit-on-error passed; five tables and owners verified\n')
    print('Encrypted backup and isolated recovery passed: ' + str(target))


def smtp(root, send):
    if send:
        # Atomic no-clobber marker is durable before SMTP authentication/submission.
        # Failure is deliberately not retryable without explicit human investigation.
        write_private(root / 'private/smtp-test.attempted', datetime.datetime.utcnow().isoformat() + 'Z\n')
    print(image_helper(root, 'smtp', *(['send-once'] if send else [])).decode().strip())
    if send:
        write_private(root / 'private/smtp-test.accepted', datetime.datetime.utcnow().isoformat() + 'Z\n')


def certificate(root, renew, dry_run=False):
    for directory in ['letsencrypt', 'certbot-work', 'certbot-logs']:
        (root / directory).mkdir(mode=0o700, exist_ok=True)
    args = ['docker', 'run', '--rm', '--network', 'host',
            '-v', str(root / 'letsencrypt') + ':/etc/letsencrypt',
            '-v', str(root / 'certbot-work') + ':/var/lib/letsencrypt',
            '-v', str(root / 'certbot-logs') + ':/var/log/letsencrypt',
            '-v', '/var/lib/tide-accounts-acme:/webroot', CERTBOT]
    if renew:
        args += ['renew', '--quiet', '--max-log-backups', '5']
        if dry_run:
            args += ['--dry-run']
    else:
        args += ['certonly', '--webroot', '-w', '/webroot', '-d', 'api.gd306.cn',
                 '--cert-name', 'api.gd306.cn', '--email', '1215742191@qq.com',
                 '--agree-tos', '--non-interactive', '--max-log-backups', '5']
    run(args, timeout=240)
    print('Certificate ' + ('renewal command' if renew else 'issuance') + ' passed')
    if renew and not dry_run:
        run(['nginx', '-t'])
        run(['nginx', '-s', 'reload'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='/opt/tide-accounts')
    parser.add_argument('command', choices=['prepare', 'check', 'check-tls', 'init-db', 'backup', 'verify-db', 'smtp-verify', 'smtp-send-once', 'certificate', 'renew', 'renew-test'])
    parser.add_argument('--smtp-source')
    args = parser.parse_args()
    os.umask(0o077)
    root = Path(args.root).resolve()
    if args.command == 'prepare':
        if not args.smtp_source:
            raise RuntimeError('A private SMTP input path is required')
        prepare(root, args.smtp_source)
    elif args.command in ['check', 'check-tls']:
        check(root, args.command == 'check-tls')
    elif args.command == 'init-db': initialize(root)
    elif args.command == 'backup': backup(root)
    elif args.command == 'verify-db': print(image_helper(root, 'database').decode().strip())
    elif args.command.startswith('smtp-'): smtp(root, args.command == 'smtp-send-once')
    else: certificate(root, args.command in ['renew', 'renew-test'], args.command == 'renew-test')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Only our explicit safe errors are rendered, never raw subprocess/data errors.
        message = str(error) if type(error) is RuntimeError else 'Operation failed (private details suppressed)'
        print(message, file=sys.stderr)
        sys.exit(1)
