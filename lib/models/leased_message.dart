/// Mirrors `App\Http\Resources\Api\V1\LeasedMessageResource`'s JSON shape
/// exactly — see the lease endpoint response.
class LeasedMessage {
  const LeasedMessage({
    required this.id,
    required this.recipientMsisdn,
    required this.body,
    required this.attemptNumber,
    required this.leaseExpiresAt,
    required this.simSlotIndex,
  });

  factory LeasedMessage.fromJson(Map<String, dynamic> json) => LeasedMessage(
        id: json['id'] as String,
        recipientMsisdn: json['recipient_msisdn'] as String,
        body: json['body'] as String,
        attemptNumber: json['attempt_number'] as int,
        leaseExpiresAt: DateTime.parse(json['lease_expires_at'] as String),
        simSlotIndex: json['sim_slot_index'] as int?,
      );

  final String id;
  final String recipientMsisdn;
  final String body;
  final int attemptNumber;
  final DateTime leaseExpiresAt;

  /// Which physical SIM to send from. Only null if the backend hasn't been
  /// upgraded to include it yet — callers must treat that as "cannot send
  /// safely" rather than guessing a slot, since guessing would silently
  /// break the server's per-SIM rate limiting.
  final int? simSlotIndex;
}
