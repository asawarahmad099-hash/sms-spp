import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_credentials.dart';
import '../services/api_client.dart';
import '../state/gateway_state.dart';

/// First-run pairing: manual entry of the device_id/public_key/secret/
/// base_url a tenant admin obtained by registering this device in the
/// portal (Devices page — "Register device"). No QR scanning in this pass;
/// see the project plan for why manual entry is the deliberate MVP choice.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController(text: 'https://');
  final _deviceIdController = TextEditingController();
  final _publicKeyController = TextEditingController();
  final _secretController = TextEditingController();

  bool _testing = false;
  String? _error;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _deviceIdController.dispose();
    _publicKeyController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _error = null;
    });

    final credentials = DeviceCredentials(
      deviceId: _deviceIdController.text.trim(),
      publicKey: _publicKeyController.text.trim(),
      secret: _secretController.text.trim(),
      baseUrl: _baseUrlController.text.trim().replaceAll(RegExp(r'/+$'), ''),
    );

    final api = ApiClient(credentials);

    try {
      // Prove the credentials actually work before persisting them — a
      // real signed request, not just a format check.
      await api.heartbeat();

      if (!mounted) return;
      await context.read<GatewayState>().pair(credentials);
    } on ApiException catch (e) {
      setState(() => _error = 'Connection test failed (${e.statusCode}): ${e.message}');
    } catch (e) {
      setState(() => _error = 'Connection test failed: $e');
    } finally {
      api.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair this device')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter the details shown when this device was registered in the '
                  'portal (Devices → Register device). They are shown only once there.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(labelText: 'API base URL', hintText: 'https://sms.example.com'),
                  keyboardType: TextInputType.url,
                  validator: (v) => (v == null || !v.startsWith('http')) ? 'Enter a valid URL' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deviceIdController,
                  decoration: const InputDecoration(labelText: 'Device ID'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _publicKeyController,
                  decoration: const InputDecoration(labelText: 'Public key', hintText: 'dev_...'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _secretController,
                  decoration: const InputDecoration(labelText: 'Secret'),
                  obscureText: true,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _testing ? null : _submit,
                  child: _testing
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Test connection & pair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
