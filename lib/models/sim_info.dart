/// One active SIM slot, as reported by the native platform channel
/// (SmsChannel.kt: listSims()) and sent up in the heartbeat's `sim_slots`.
class SimInfo {
  const SimInfo({
    required this.slotIndex,
    required this.subscriptionId,
    required this.carrierName,
    required this.phoneNumber,
  });

  factory SimInfo.fromMap(Map<Object?, Object?> map) => SimInfo(
        slotIndex: map['slotIndex'] as int,
        subscriptionId: map['subscriptionId'] as int,
        carrierName: map['carrierName'] as String?,
        phoneNumber: map['phoneNumber'] as String?,
      );

  /// Physical slot position (0, 1, ...) — this is what the backend's
  /// `sim_profiles.slot_index` and the lease response's `sim_slot_index`
  /// refer to.
  final int slotIndex;

  /// Android's subscription ID — what SmsManager actually needs to pick the
  /// right SIM when sending, distinct from slotIndex.
  final int subscriptionId;

  final String? carrierName;
  final String? phoneNumber;

  Map<String, dynamic> toHeartbeatJson() => {
        'slot_index': slotIndex,
        'operator_name': carrierName,
        'msisdn': phoneNumber,
      };
}
