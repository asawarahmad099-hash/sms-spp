import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/device_credentials.dart';
import '../models/leased_message.dart';
import '../models/sim_info.dart';
import '../services/api_client.dart';
import '../services/credentials_store.dart';
import '../services/local_db.dart';
import '../services/sim_service.dart';
import 'package:sms_channel/sms_channel.dart';

/// The callback flutter_foreground_task's native side invokes to bootstrap
/// the background isolate. Must stay a top-level/static function, and the
/// `vm:entry-point` pragma is required so tree-shaking doesn't strip it —
/// see main.dart for where this is passed to FlutterForegroundTask.startService.
@pragma('vm:entry-point')
void gatewayTaskCallback() {
  FlutterForegroundTask.setTaskHandler(GatewayTaskHandler());
}

/// Heartbeat/lease/send/report loop. Runs in its own isolate, kept alive by
/// the Android foreground service — see GatewayApplication.kt for why
/// plugin calls (sqflite, flutter_secure_storage, sms_channel) work at all
/// here, which is not automatic with this package.
class GatewayTaskHandler extends TaskHandler {
  static const _heartbeatInterval = Duration(seconds: 60);
  static const _leaseIntervalIdle = Duration(seconds: 30);
  static const _leaseIntervalActive = Duration(seconds: 7);
  static const _lowWaterMark = 5;
  static const _leaseLimit = 10;

  final _db = LocalDb.instance;
  final _simService = const SimService();

  DeviceCredentials? _credentials;
  ApiClient? _api;

  DateTime? _lastHeartbeatAt;
  DateTime _nextLeaseAllowedAt = DateTime.now();
  List<SimInfo> _knownSims = [];

  /// True once /lease has returned 403 (pending approval, disabled, or the
  /// tenant itself is suspended) — heartbeats continue, leasing pauses.
  bool _leasingBlocked = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _credentials = await const CredentialsStore().load();

    if (_credentials == null) {
      await _db.log('error', 'Task started with no stored credentials — stopping.');
      await FlutterForegroundTask.stopService();
      return;
    }

    _api = ApiClient(_credentials!);
    await _db.log('info', 'Gateway service started (starter: ${starter.name}).');
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_tick());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _db.log('info', 'Gateway service stopped (timeout: $isTimeout).');
    _api?.close();
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}

  Future<void> _tick() async {
    final api = _api;
    if (api == null) return;

    try {
      await _retryPendingReports(api);
      await _dropStaleUnsent();

      if (_lastHeartbeatAt == null || DateTime.now().difference(_lastHeartbeatAt!) >= _heartbeatInterval) {
        await _heartbeat(api);
      }

      if (!_leasingBlocked && DateTime.now().isAfter(_nextLeaseAllowedAt)) {
        await _leaseAndProcess(api);
      }

      await _updateNotification();
    } catch (e) {
      await _db.log('error', 'Tick failed: $e');
      FlutterForegroundTask.sendDataToMain({'type': 'error', 'message': e.toString()});
    }
  }

  Future<void> _heartbeat(ApiClient api) async {
    try {
      _knownSims = await _simService.listSims();
    } catch (e) {
      await _db.log('warn', 'Could not read SIM list: $e');
    }

    try {
      await api.heartbeat(
        osVersion: Platform.operatingSystemVersion,
        simSlots: _knownSims,
      );
      _lastHeartbeatAt = DateTime.now();
      FlutterForegroundTask.sendDataToMain({'type': 'heartbeat_ok', 'sims': _knownSims.length});
    } on ApiException catch (e) {
      await _db.log('error', 'Heartbeat failed: $e');
    }
  }

  Future<void> _leaseAndProcess(ApiClient api) async {
    final depth = await _db.queueDepth();
    if (depth >= _lowWaterMark) {
      _nextLeaseAllowedAt = DateTime.now().add(_leaseIntervalActive);
      return;
    }

    List<LeasedMessage> leased;
    try {
      leased = await api.lease(limit: _leaseLimit);
    } on ApiException catch (e) {
      if (e.isForbidden) {
        _leasingBlocked = true;
        await _db.log('warn', 'Leasing blocked (device not approved, disabled, or tenant suspended): ${e.message}');
        FlutterForegroundTask.sendDataToMain({'type': 'leasing_blocked', 'message': e.message});
      } else {
        await _db.log('error', 'Lease failed: $e');
      }
      _nextLeaseAllowedAt = DateTime.now().add(_leaseIntervalIdle);
      return;
    }

    if (leased.isEmpty) {
      _nextLeaseAllowedAt = DateTime.now().add(_leaseIntervalIdle);
      return;
    }

    for (final message in leased) {
      // Persist BEFORE sending — see LocalDb's doc comment for why this
      // ordering is what makes a mid-send crash recoverable rather than
      // silently losing or double-sending a message.
      await _db.enqueueLeased(
        messageId: message.id,
        recipientMsisdn: message.recipientMsisdn,
        body: message.body,
        simSlotIndex: message.simSlotIndex,
        leaseExpiresAt: message.leaseExpiresAt,
        attemptNumber: message.attemptNumber,
      );

      await _sendAndReport(api, message);
    }

    _nextLeaseAllowedAt = DateTime.now().add(_leaseIntervalActive);
  }

  Future<void> _sendAndReport(ApiClient api, LeasedMessage message) async {
    final subscriptionId = _resolveSubscriptionId(message.simSlotIndex);

    if (subscriptionId == null) {
      await _db.log('error', 'No SIM for slot ${message.simSlotIndex} — cannot send ${message.id}.');
      await api.report(
        messageId: message.id,
        result: 'rejected',
        state: 'FAILED',
        errorCode: 'NO_MATCHING_SIM',
        errorMessage: 'Device has no active SIM at slot ${message.simSlotIndex}.',
      );
      await _db.removeFromQueue(message.id);
      return;
    }

    final stopwatch = Stopwatch()..start();
    String result;
    String state;
    String? errorCode;
    String? errorMessage;

    try {
      await _simService.send(subscriptionId: subscriptionId, recipient: message.recipientMsisdn, body: message.body);
      result = 'success';
      state = 'SUBMITTED';
    } on SmsChannelException catch (e) {
      result = 'failed';
      state = 'FAILED';
      errorCode = e.code;
      errorMessage = e.message;
    }
    stopwatch.stop();

    // Sent (or definitively failed to send) — mark this BEFORE the report
    // call. If the app dies between here and the report succeeding, the
    // next tick's _retryPendingReports() retries the report, never the send.
    await _db.markSentPendingReport(message.id);

    try {
      await api.report(
        messageId: message.id,
        result: result,
        state: state,
        errorCode: errorCode,
        errorMessage: errorMessage,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      await _db.removeFromQueue(message.id);
      await _db.log(result == 'success' ? 'info' : 'warn', '$state ${message.id} -> ${message.recipientMsisdn}');
    } on ApiException catch (e) {
      // Left as sent_pending_report — retried next tick.
      await _db.log('warn', 'Report call failed for ${message.id}, will retry: $e');
    }
  }

  /// Retries the *report* call (never a re-send) for anything the app sent
  /// but never confirmed the server received the report for.
  Future<void> _retryPendingReports(ApiClient api) async {
    final pending = await _db.pendingReports();

    for (final row in pending) {
      // We don't persist the original result/state — a message that made
      // it to `sent_pending_report` was, by construction, always the
      // successful-send path (the failure branch above reports inline
      // before ever marking sent_pending_report), so retrying always means
      // SUBMITTED/success.
      try {
        await api.report(messageId: row['message_id'] as String, result: 'success', state: 'SUBMITTED');
        await _db.removeFromQueue(row['message_id'] as String);
      } on ApiException catch (e) {
        await _db.log('warn', 'Retry report still failing for ${row['message_id']}: $e');
      }
    }
  }

  Future<void> _dropStaleUnsent() async {
    final stale = await _db.staleUnsent();

    for (final row in stale) {
      await _db.log('warn', 'Dropping stale unsent lease for ${row['message_id']} (server already reclaimed it).');
      await _db.removeFromQueue(row['message_id'] as String);
    }
  }

  int? _resolveSubscriptionId(int? simSlotIndex) {
    if (simSlotIndex == null) return null;

    for (final sim in _knownSims) {
      if (sim.slotIndex == simSlotIndex) return sim.subscriptionId;
    }

    return null;
  }

  Future<void> _updateNotification() async {
    final depth = await _db.queueDepth();
    final status = _leasingBlocked ? 'Awaiting approval' : 'Active';

    FlutterForegroundTask.updateService(
      notificationTitle: 'SMS Gateway — $status',
      notificationText: '$depth message(s) in local queue · ${_knownSims.length} SIM(s)',
    );
  }
}
