import 'package:flutter/foundation.dart';

import '../models/device_credentials.dart';
import '../services/credentials_store.dart';

enum GatewayConnectionStatus { unknown, pendingApproval, active, disabledOrTenantSuspended, offline }

/// UI-facing state, kept separate from the background task's own internal
/// loop state — the foreground task handler runs in a different isolate and
/// can't share a ChangeNotifier directly with the UI isolate, so it reports
/// back through FlutterForegroundTask's own data channel (see
/// gateway_task_handler.dart / status_screen.dart) rather than this class
/// mutating itself from the background. This class only owns what the UI
/// isolate itself needs: whether we're paired, and the credentials.
class GatewayState extends ChangeNotifier {
  GatewayState({this._store = const CredentialsStore()});

  final CredentialsStore _store;

  DeviceCredentials? _credentials;
  bool _loading = true;

  DeviceCredentials? get credentials => _credentials;
  bool get isPaired => _credentials != null;
  bool get loading => _loading;

  Future<void> loadFromStorage() async {
    _credentials = await _store.load();
    _loading = false;
    notifyListeners();
  }

  Future<void> pair(DeviceCredentials credentials) async {
    await _store.save(credentials);
    _credentials = credentials;
    notifyListeners();
  }

  Future<void> unpair() async {
    await _store.clear();
    _credentials = null;
    notifyListeners();
  }
}
