import 'package:flutter/services.dart';

/// One active SIM slot as reported by the native side.
class SmsChannelSimInfo {
  const SmsChannelSimInfo({
    required this.slotIndex,
    required this.subscriptionId,
    this.carrierName,
    this.phoneNumber,
  });

  factory SmsChannelSimInfo.fromMap(Map<Object?, Object?> map) => SmsChannelSimInfo(
        slotIndex: map['slotIndex'] as int,
        subscriptionId: map['subscriptionId'] as int,
        carrierName: map['carrierName'] as String?,
        phoneNumber: map['phoneNumber'] as String?,
      );

  final int slotIndex;
  final int subscriptionId;
  final String? carrierName;
  final String? phoneNumber;
}

/// Thrown when the native side reports a send failure — [code] mirrors the
/// PlatformException code raised by SmsChannelPlugin.kt (PERMISSION_DENIED,
/// SEND_FAILED, INVALID_ARGS).
class SmsChannelException implements Exception {
  SmsChannelException(this.code, this.message);

  final String code;
  final String? message;

  @override
  String toString() => 'SmsChannelException($code): $message';
}

/// Native SMS sending + multi-SIM enumeration, deliberately hand-written
/// (not a third-party package — see the project plan's rationale) and
/// packaged as a real local Flutter plugin rather than a MainActivity-only
/// channel, specifically so it auto-registers on every FlutterEngine the
/// app creates — including flutter_foreground_task's background isolate,
/// which does NOT get MainActivity's channels and would otherwise throw
/// MissingPluginException the moment the background loop tried to send.
class SmsChannel {
  SmsChannel._();

  static const MethodChannel _channel = MethodChannel('com.smsplatform.sms_gateway/sms');

  static Future<List<SmsChannelSimInfo>> listSims() async {
    final result = await _channel.invokeMethod<List<Object?>>('listSims');

    return (result ?? [])
        .map((e) => SmsChannelSimInfo.fromMap(e! as Map<Object?, Object?>))
        .toList();
  }

  /// Sends [body] to [recipient] from the SIM identified by [subscriptionId]
  /// (from [SmsChannelSimInfo.subscriptionId] — NOT slotIndex; only
  /// subscriptionId is meaningful to Android's SmsManager). Splits into a
  /// multipart SMS natively if the body exceeds one segment.
  static Future<void> sendSms({
    required int subscriptionId,
    required String recipient,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>('sendSms', {
        'subscriptionId': subscriptionId,
        'recipient': recipient,
        'body': body,
      });
    } on PlatformException catch (e) {
      throw SmsChannelException(e.code, e.message);
    }
  }
}
