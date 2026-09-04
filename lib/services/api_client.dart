import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/device_credentials.dart';
import '../models/leased_message.dart';
import '../models/sim_info.dart';
import 'hmac_signer.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isForbidden => statusCode == 403;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Talks to the Laravel /v1 API using this device's own HMAC credentials.
/// Every call builds the JSON body once, signs those exact bytes, and sends
/// those exact bytes — see HmacSigner's doc comment for why that ordering
/// matters (a client that re-serializes the body separately from what it
/// signed would silently break every request).
class ApiClient {
  ApiClient(this.credentials, {this.signer = const HmacSigner(), http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final DeviceCredentials credentials;
  final HmacSigner signer;
  final http.Client _http;
  static const _uuid = Uuid();

  Future<http.Response> _send(String method, String path, {Map<String, dynamic>? body}) async {
    final bodyBytes = utf8.encode(body == null ? '' : jsonEncode(body));
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _uuid.v4();

    final headers = signer.headersFor(
      method: method,
      path: path,
      publicKey: credentials.publicKey,
      secret: credentials.secret,
      bodyBytes: bodyBytes,
      timestamp: timestamp,
      nonce: nonce,
    );

    final uri = Uri.parse('${credentials.baseUrl}$path');
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = bodyBytes;

    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode >= 400) {
      final decoded = response.body.isEmpty ? {} : jsonDecode(response.body);
      throw ApiException(response.statusCode, (decoded is Map ? decoded['message'] : null) ?? response.body);
    }

    return response;
  }

  Future<void> heartbeat({
    String? appVersion,
    String? osVersion,
    int? batteryLevel,
    String? networkType,
    List<SimInfo> simSlots = const [],
  }) async {
    await _send(
      'POST',
      '/api/v1/devices/${credentials.deviceId}/heartbeat',
      body: {
        if (appVersion != null) 'app_version': appVersion,
        if (osVersion != null) 'os_version': osVersion,
        if (batteryLevel != null) 'battery_level': batteryLevel,
        if (networkType != null) 'network_type': networkType,
        if (simSlots.isNotEmpty) 'sim_slots': simSlots.map((s) => s.toHeartbeatJson()).toList(),
      },
    );
  }

  Future<List<LeasedMessage>> lease({int limit = 10}) async {
    final response = await _send(
      'POST',
      '/api/v1/devices/${credentials.deviceId}/lease',
      body: {'limit': limit},
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as List<dynamic>;

    return data.map((e) => LeasedMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> report({
    required String messageId,
    required String result,
    required String state,
    String? errorCode,
    String? errorMessage,
    int? latencyMs,
  }) async {
    await _send(
      'POST',
      '/api/v1/devices/${credentials.deviceId}/messages/$messageId/report',
      body: {
        'result': result,
        'state': state,
        if (errorCode != null) 'error_code': errorCode,
        if (errorMessage != null) 'error_message': errorMessage,
        if (latencyMs != null) 'latency_ms': latencyMs,
      },
    );
  }

  void close() => _http.close();
}
