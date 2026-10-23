#!/usr/bin/env python3
"""Amended deployment boundaries only; all credentials/rows/logs are synthetic."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import secrets
import shutil
import stat
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('ops', str(HERE / 'ops.py'))
ops = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ops)


class Boundaries(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix='tide-deploy-boundaries-')
        self.root = Path(self.fixture.name)
        self.root.chmod(0o700)
        for name in ['compose.yaml', 'verify.mjs']:
            shutil.copyfile(str(HERE / name), str(self.root / name))
            (self.root / name).chmod(0o644)
        source = self.root / 'synthetic-smtp.input'
        ops.write_private(source, 'synthetic-fixture-only\n')
        with contextlib.redirect_stdout(io.StringIO()):
            ops.prepare(self.root, str(source))

    def tearDown(self):
        self.fixture.cleanup()

    def test_compose_override_cannot_replace_reviewed_image(self):
        with patch.dict(os.environ, {'ACCOUNTS_IMAGE': 'unreviewed.invalid:synthetic'}):
            config = json.loads(ops.compose(self.root, 'config', '--format', 'json'))
            self.assertEqual(config['services']['api']['image'], ops.IMAGE_ID)
            self.assertEqual(config['services']['api']['pull_policy'], 'never')
            with contextlib.redirect_stdout(io.StringIO()):
                ops.check(self.root)  # Actual immutable image parser, network none.
            # Exercise Compose's actual pinned-image execution path; no API/SMTP starts.
            ops.compose(self.root, 'run', '--rm', '--no-deps', 'api', 'node', '-e',
                        'if(process.getuid()===0)process.exit(1)')

    def test_actual_resolved_image_mismatch_rejected_before_image_run(self):
        path = self.root / 'compose.yaml'
        path.write_text(path.read_text().replace(ops.IMAGE_ID, 'unreviewed.invalid:synthetic'))
        with self.assertRaisesRegex(RuntimeError, 'Resolved Compose API image'):
            ops.check(self.root)

    def test_marker_file_and_directory_fsync_precede_synthetic_send(self):
        events = []
        original = os.fsync

        def sync(fd):
            original(fd)  # Exercise real file/directory fsync, not a no-op mock.
            events.append('directory-sync' if stat.S_ISDIR(os.fstat(fd).st_mode) else 'file-sync')

        def synthetic_send(root, *args):
            self.assertEqual(events, ['file-sync', 'directory-sync'])
            self.assertTrue((root / 'private/smtp-test.attempted').is_file())
            events.append('synthetic-send')
            return b'Synthetic SMTP fixture accepted; no network\n'

        with patch.object(ops.os, 'fsync', side_effect=sync), patch.object(ops, 'image_helper', side_effect=synthetic_send):
            with contextlib.redirect_stdout(io.StringIO()):
                ops.smtp(self.root, True)
        self.assertEqual(events, ['file-sync', 'directory-sync', 'synthetic-send', 'file-sync', 'directory-sync'])
        with patch.object(ops, 'image_helper') as send:
            with self.assertRaises(FileExistsError):
                ops.smtp(self.root, True)
            send.assert_not_called()

    def test_marker_fsync_failure_never_invokes_synthetic_send(self):
        with patch.object(ops.os, 'fsync', side_effect=OSError('synthetic fsync failure')), patch.object(ops, 'image_helper') as send:
            with self.assertRaises(OSError):
                ops.smtp(self.root, True)
            send.assert_not_called()
        self.assertTrue((self.root / 'private/smtp-test.attempted').exists())

    def test_synthetic_database_errors_do_not_log_values(self):
        config = json.loads(ops.compose(self.root, 'config', '--format', 'json'))['services']['db']
        sentinel = 'synthetic-sensitive-row@example.invalid'
        primary = 'synthetic-primary-error@example.invalid'
        migration = (HERE.parent / 'migrations/001_accounts.sql').read_text()
        failures = [
            "INSERT INTO email_accounts(id,email) VALUES('00000000-0000-4000-8000-000000000002','" + sentinel + "');",
            "INSERT INTO email_challenges(id,email,code_hash,attempts,state,expires_at) VALUES('00000000-0000-4000-8000-000000000003','" + sentinel + "','" + 'a' * 64 + "',6,'delivered',now());",
            "SELECT '" + primary + "'::uuid;",
        ]

        def exercise(command, expect_private):
            name = 'tide-accounts-logging-' + secrets.token_hex(4) + '-test'
            database = 'tide_accounts_logging_test'
            args = ['docker', 'run', '-d', '--name', name, '--network', 'none', '--read-only',
                    '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
                    '--tmpfs', '/var/lib/postgresql/data', '--tmpfs', '/var/run/postgresql:mode=3777',
                    '--tmpfs', '/tmp', '-e', 'POSTGRES_DB=' + database,
                    '-e', 'POSTGRES_HOST_AUTH_METHOD=trust']
            for capability in config['cap_add']:
                args += ['--cap-add', capability]
            args += [config['image']] + command

            def sql(statement):
                return subprocess.run(['docker', 'exec', '-i', name, 'psql', '-X', '-qAt',
                                       '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-p', '55439',
                                       '-d', database], input=statement.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)

            try:
                ops.run(args)
                for _ in range(60):
                    if sql('SELECT 1;').returncode == 0:
                        # Init entrypoint has a temporary server; ensure final PID1
                        # postgres (rather than its init shell) before testing logs.
                        process = ops.run(['docker', 'exec', name, 'cat', '/proc/1/comm']).strip()
                        if process == b'postgres':
                            break
                    time.sleep(0.5)
                else:
                    self.fail('Synthetic test DB did not become ready')
                self.assertEqual(sql(migration).returncode, 0)
                self.assertEqual(sql("INSERT INTO email_accounts(id,email) VALUES('00000000-0000-4000-8000-000000000001','" + sentinel + "');").returncode, 0)
                for statement in failures:
                    result = sql(statement)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue(sentinel.encode() in result.stderr or primary.encode() in result.stderr)
                # Docker postgres writes server messages on stderr; capture both.
                result = subprocess.run(['docker', 'logs', name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(result.returncode, 0)
                logs = result.stdout + result.stderr
                if expect_private:
                    self.assertNotIn(sentinel.encode(), logs)
                    self.assertNotIn(primary.encode(), logs)
                    self.assertNotIn(b'DETAIL:', logs)
                    expected = {'log_min_messages': 'panic', 'log_error_verbosity': 'terse',
                                'log_parameter_max_length': '0', 'log_parameter_max_length_on_error': '0'}
                    for setting, value in expected.items():
                        self.assertEqual(sql('SHOW ' + setting + ';').stdout.strip().decode(), value)
                else:
                    self.assertIn(sentinel.encode(), logs)  # Positive control of the original defect.
                    self.assertIn(primary.encode(), logs)
            finally:
                # Disposable synthetic namespace/tmpfs only. Never mounts production volume.
                subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        exercise(['postgres', '-c', 'listen_addresses=127.0.0.1', '-p', '55439',
                  '-c', 'log_statement=none', '-c', 'log_min_error_statement=panic'], False)
        exercise(config['command'], True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
