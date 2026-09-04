import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/device_credentials.dart';

/// Android-Keystore-backed storage for the device's own keypair — the one
/// thing in this app that must never end up in the plain sqflite DB or
/// SharedPreferences.
class CredentialsStore {
  const CredentialsStore();

  // v11's default AndroidOptions() already uses AES-GCM data encryption with
  // RSA-OAEP KeyStore key wrapping unconditionally — no extra flag needed.
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

  static const _deviceIdKey = 'device_id';
  static const _publicKeyKey = 'public_key';
  static const _secretKey = 'secret';
  static const _baseUrlKey = 'base_url';

  Future<void> save(DeviceCredentials credentials) async {
    await _storage.write(key: _deviceIdKey, value: credentials.deviceId);
    await _storage.write(key: _publicKeyKey, value: credentials.publicKey);
    await _storage.write(key: _secretKey, value: credentials.secret);
    await _storage.write(key: _baseUrlKey, value: credentials.baseUrl);
  }

  Future<DeviceCredentials?> load() async {
    final all = await _storage.readAll();

    if (!all.containsKey(_deviceIdKey) || !all.containsKey(_secretKey)) {
      return null;
    }

    return DeviceCredentials(
      deviceId: all[_deviceIdKey]!,
      publicKey: all[_publicKeyKey]!,
      secret: all[_secretKey]!,
      baseUrl: all[_baseUrlKey]!,
    );
  }

  Future<void> clear() async {
    await _storage.deleteAll();
  }
}
