import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_gateway/services/hmac_signer.dart';

/// Fixed vectors generated from the real PHP implementation
/// (App\Services\Api\HmacSignatureService) via `php artisan tinker`, so this
/// test proves the Dart port matches the server byte-for-byte — the single
/// most likely place for a silent, hard-to-debug bug (a mismatched body
/// encoding or path format would make every request 401).
void main() {
  const signer = HmacSigner();

  test('matches the PHP signature for a POST request with a JSON body', () {
    final canonical = signer.canonicalString(
      method: 'POST',
      path: '/api/v1/devices/abc123/lease',
      timestamp: '1700000000',
      nonce: '11111111-1111-1111-1111-111111111111',
      bodyBytes: utf8.encode('{"limit":10}'),
    );

    expect(
      signer.sign(canonical, 'top-secret-value'),
      'fIA4NkINm4F+VJQKrqJDKnjy2wYRCT4fobg1wZHqb/w=',
    );
  });

  test('matches the PHP signature for a GET request with no body', () {
    final canonical = signer.canonicalString(
      method: 'GET',
      path: '/api/v1/devices/abc123/heartbeat',
      timestamp: '1700000500',
      nonce: '22222222-2222-2222-2222-222222222222',
      bodyBytes: utf8.encode(''),
    );

    expect(
      signer.sign(canonical, 'another-secret'),
      'hBqhY4HdPr25GagRQjQ56Wb+066LkIVVdv/i1GLPZJc=',
    );
  });

  test('matches the PHP signature for a report POST with a nested body', () {
    final canonical = signer.canonicalString(
      method: 'POST',
      path: '/api/v1/devices/abc123/messages/msg-1/report',
      timestamp: '1700001000',
      nonce: '33333333-3333-3333-3333-333333333333',
      bodyBytes: utf8.encode('{"result":"success","state":"DELIVERED"}'),
    );

    expect(
      signer.sign(canonical, 'third-secret-xyz'),
      'sVA7LaMg+jivsOW/EAgegjbHlPGJf/VbGTE62wO2sbg=',
    );
  });

  test('lowercases method casing consistently and rejects a mismatched signature', () {
    final canonical = signer.canonicalString(
      method: 'post',
      path: '/api/v1/devices/abc123/lease',
      timestamp: '1700000000',
      nonce: '11111111-1111-1111-1111-111111111111',
      bodyBytes: utf8.encode('{"limit":10}'),
    );

    expect(signer.sign(canonical, 'top-secret-value'), 'fIA4NkINm4F+VJQKrqJDKnjy2wYRCT4fobg1wZHqb/w=');
    expect(signer.sign(canonical, 'wrong-secret'), isNot('fIA4NkINm4F+VJQKrqJDKnjy2wYRCT4fobg1wZHqb/w='));
  });

  test('headersFor() builds all four required headers', () {
    final headers = signer.headersFor(
      method: 'POST',
      path: '/api/v1/devices/abc123/lease',
      publicKey: 'dev_abc',
      secret: 'top-secret-value',
      bodyBytes: utf8.encode('{"limit":10}'),
      timestamp: '1700000000',
      nonce: '11111111-1111-1111-1111-111111111111',
    );

    expect(headers['X-API-Key'], 'dev_abc');
    expect(headers['X-Timestamp'], '1700000000');
    expect(headers['X-Nonce'], '11111111-1111-1111-1111-111111111111');
    expect(headers['X-Signature'], 'fIA4NkINm4F+VJQKrqJDKnjy2wYRCT4fobg1wZHqb/w=');
  });
}
