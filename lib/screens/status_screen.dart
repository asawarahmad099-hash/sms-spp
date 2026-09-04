import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../background/gateway_task_handler.dart';
import '../state/gateway_state.dart';
import 'log_screen.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _serviceRunning = false;
  Object? _lastData;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    _refreshServiceState();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    super.dispose();
  }

  void _onData(Object data) {
    setState(() => _lastData = data);
  }

  Future<void> _refreshServiceState() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) setState(() => _serviceRunning = running);
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.sms,
      Permission.phone,
    ].request();

    final allGranted = statuses.values.every((s) => s.isGranted);

    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    return allGranted;
  }

  Future<void> _start() async {
    final granted = await _ensurePermissions();

    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS and phone-state permissions are required to send messages.')),
        );
      }
      return;
    }

    if (Platform.isAndroid && !await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    final result = await (await FlutterForegroundTask.isRunningService
        ? FlutterForegroundTask.restartService()
        : FlutterForegroundTask.startService(
            serviceId: 1,
            notificationTitle: 'SMS Gateway',
            notificationText: 'Starting…',
            callback: gatewayTaskCallback,
          ));

    if (result is ServiceRequestSuccess) {
      await _refreshServiceState();
    }
  }

  Future<void> _stop() async {
    await FlutterForegroundTask.stopService();
    await _refreshServiceState();
  }

  Future<void> _unpair() async {
    if (_serviceRunning) await _stop();
    if (!mounted) return;
    await context.read<GatewayState>().unpair();
  }

  @override
  Widget build(BuildContext context) {
    final credentials = context.watch<GatewayState>().credentials!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gateway status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Event log',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _serviceRunning ? Icons.check_circle : Icons.pause_circle,
                          color: _serviceRunning ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _serviceRunning ? 'Running' : 'Stopped',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Device ID: ${credentials.deviceId}'),
                    Text('Server: ${credentials.baseUrl}'),
                    if (_lastData != null) ...[
                      const SizedBox(height: 8),
                      Text('Last update: $_lastData', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _serviceRunning ? _stop : _start,
              icon: Icon(_serviceRunning ? Icons.stop : Icons.play_arrow),
              label: Text(_serviceRunning ? 'Stop gateway' : 'Start gateway'),
            ),
            const SizedBox(height: 24),
            TextButton(onPressed: _unpair, child: const Text('Unpair this device')),
          ],
        ),
      ),
    );
  }
}
