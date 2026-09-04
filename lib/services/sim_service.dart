import 'package:sms_channel/sms_channel.dart';

import '../models/sim_info.dart';

/// Thin wrapper around the local `sms_channel` plugin (see its own doc
/// comment for why this is a hand-written plugin, not a package, and why it
/// has to BE a plugin rather than MainActivity-only code).
class SimService {
  const SimService();

  Future<List<SimInfo>> listSims() async {
    final result = await SmsChannel.listSims();

    return result
        .map((s) => SimInfo(
              slotIndex: s.slotIndex,
              subscriptionId: s.subscriptionId,
              carrierName: s.carrierName,
              phoneNumber: s.phoneNumber,
            ))
        .toList();
  }

  /// Throws [SmsChannelException] on failure (permission denied, send
  /// failure) — callers report that back via /report rather than assuming
  /// success.
  Future<void> send({required int subscriptionId, required String recipient, required String body}) {
    return SmsChannel.sendSms(subscriptionId: subscriptionId, recipient: recipient, body: body);
  }
}
