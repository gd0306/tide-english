#!/usr/bin/env python3
"""Synthetic public checks only: never sends email or authenticates a real account."""
import argparse
import http.client
import json
import socket
import ssl

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--direct-ip', help='Optional fixed authorized host, preserving TLS SNI verification')
parser.add_argument('--interface', help='macOS physical interface; no global route/proxy changes')
parser.add_argument('--ca-file', help='Optional trusted system CA bundle when Python has no installed bundle')
args = parser.parse_args()


class Connection(http.client.HTTPSConnection):
    def connect(self):
        if not args.direct_ip:
            return super().connect()
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(15)
        if args.interface:
            sock.setsockopt(socket.IPPROTO_IP, 25, socket.if_nametoindex(args.interface))
        sock.connect((args.direct_ip, 443))
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)


connection = Connection('api.gd306.cn', timeout=15, context=ssl.create_default_context(cafile=args.ca_file))


def request(method, path, body=None, headers=None):
    values = {'Content-Type': 'application/json', **(headers or {})}
    connection.request(method, path, body, values)
    response = connection.getresponse()
    payload = response.read(4097)
    assert len(payload) <= 4096, 'Response unexpectedly large'
    assert response.getheader('Cache-Control') == 'no-store', 'Missing no-store'
    data = json.loads(payload)
    return response.status, data


def error(method, path, status, code, body=None):
    actual, data = request(method, path, body)
    assert actual == status and data == {'error': {'code': code}}, 'Safe error contract mismatch'


try:
    status, health = request('GET', '/healthz')
    assert status == 200 and health == {
        'ok': True, 'service': 'tide-email-accounts', 'revision': '83c960f',
        'hostedVoice': False, 'livePayments': False, 'learningSync': False,
    }, 'Health/revision/gates mismatch'
    assert request('GET', '/readyz') == (200, {'ok': True})
    error('GET', '/v1/not-a-route', 404, 'not_found')
    error('POST', '/v1/email-auth/challenge', 400, 'invalid_request', '{')
    error('POST', '/v1/email-auth/challenge', 400, 'invalid_request', '{"email":"invalid"}')
    error('POST', '/v1/email-auth/challenge', 400, 'invalid_request', '{"email":"synthetic@example.invalid","unexpected":true}')
    error('POST', '/v1/email-auth/challenge', 413, 'request_too_large', json.dumps({'email': 'x' * 3000}))
    error('GET', '/v1/email-account', 401, 'invalid_session')
    error('POST', '/v1/email-auth/refresh', 401, 'invalid_session', '{"refreshToken":"synthetic-invalid"}')
    error('POST', '/v1/email-auth/verify', 400, 'invalid_request', '{"challengeID":"synthetic-invalid","code":"000000"}')
    error('DELETE', '/v1/email-account', 400, 'invalid_request', '{"challengeID":"synthetic-invalid","code":"000000"}')
    assert request('POST', '/v1/email-auth/sign-out', '{"refreshToken":"synthetic-invalid"}') == (200, {'signedOut': True})
    print('PASS: trusted TLS, exact revision/readiness, all hosted gates off, safe contracts/no-store, 2KiB limit; no challenge delivered')
    limited = False
    for n in range(121):
        status, data = request('GET', '/v1/email-account', headers={'X-Forwarded-For': '198.51.100.' + str(n % 250 + 1)})
        if status == 429:
            assert data == {'error': {'code': 'rate_limited'}}
            limited = True
            break
        assert status == 401 and data == {'error': {'code': 'invalid_session'}}
    assert limited, 'Forged forwarding headers bypassed admission'
    for n in range(3):
        status, data = request('GET', '/v1/email-account', headers={'X-Forwarded-For': '203.0.113.' + str(n + 1)})
        assert status == 429 and data == {'error': {'code': 'rate_limited'}}
    print('PASS: bounded public client admission, spoofed forwarding headers cannot bypass rate limit')
finally:
    connection.close()
