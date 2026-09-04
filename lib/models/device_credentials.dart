/// The device's own identity/keypair, obtained by a tenant admin registering
/// this device in the portal and entering the result here (manual pairing —
/// see pairing_screen.dart). Persisted in flutter_secure_storage, never in
/// the plain sqflite DB.
class DeviceCredentials {
  const DeviceCredentials({
    required this.deviceId,
    required this.publicKey,
    required this.secret,
    required this.baseUrl,
  });

  final String deviceId;
  final String publicKey;
  final String secret;

  /// e.g. https://sms.example.com — no trailing slash.
  final String baseUrl;

  Map<String, String> toMap() => {
        'device_id': deviceId,
        'public_key': publicKey,
        'secret': secret,
        'base_url': baseUrl,
      };

  static DeviceCredentials fromMap(Map<String, String> map) => DeviceCredentials(
        deviceId: map['device_id']!,
        publicKey: map['public_key']!,
        secret: map['secret']!,
        baseUrl: map['base_url']!,
      );
}
