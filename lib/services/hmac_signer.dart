import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Builds and signs requests exactly the way the Laravel backend's
/// `App\Services\Api\HmacSignatureService` verifies them:
///
///   canonical = METHOD "\n" PATH "\n" TIMESTAMP "\n" NONCE "\n" SHA256_HEX(body)
///   signature = base64(HMAC_SHA256(canonical, secret))
///
/// `path` must be the literal request path with a leading "/" (e.g.
/// `/api/v1/devices/{id}/lease`) — exactly what the HTTP client calls,
/// matching Laravel's `$request->path()` server-side. `bodyBytes` must be
/// the exact UTF-8 bytes actually transmitted; build the JSON string once,
/// encode it once, sign those bytes, and send those exact bytes — never let
/// the HTTP client re-serialize a map separately, or a key-ordering
/// difference will silently break every signature.
class HmacSigner {
  const HmacSigner();

  String canonicalString({
    required String method,
    required String path,
    required String timestamp,
    required String nonce,
    required List<int> bodyBytes,
  }) {
    final bodyHash = sha256.convert(bodyBytes).toString();

    return [method.toUpperCase(), path, timestamp, nonce, bodyHash].join('\n');
  }

  String sign(String canonical, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));

    return base64.encode(hmac.convert(utf8.encode(canonical)).bytes);
  }

  /// Convenience: builds the four `X-*` headers for one signed request.
  Map<String, String> headersFor({
    required String method,
    required String path,
    required String publicKey,
    required String secret,
    required List<int> bodyBytes,
    required String timestamp,
    required String nonce,
  }) {
    final canonical = canonicalString(
      method: method,
      path: path,
      timestamp: timestamp,
      nonce: nonce,
      bodyBytes: bodyBytes,
    );

    return {
      'X-API-Key': publicKey,
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      'X-Signature': sign(canonical, secret),
      'Content-Type': 'application/json',
    };
  }
}
