import 'package:flutter/material.dart';

import '../services/local_db.dart';

/// Bounded local event log (LocalDb caps it at LocalDb.eventLogCap rows) —
/// satisfies the platform spec's "Bounded local event log" gateway module.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  late Future<List<Map<String, Object?>>> _events;

  @override
  void initState() {
    super.initState();
    _events = LocalDb.instance.recentEvents();
  }

  Future<void> _refresh() async {
    setState(() => _events = LocalDb.instance.recentEvents());
    await _events;
  }

  Color _colorFor(BuildContext context, String level) {
    return switch (level) {
      'error' => Theme.of(context).colorScheme.error,
      'warn' => Colors.orange,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Event log')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: _events,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final events = snapshot.data!;

            if (events.isEmpty) {
              return const Center(child: Text('No events yet.'));
            }

            return ListView.separated(
              itemCount: events.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final event = events[index];
                return ListTile(
                  dense: true,
                  title: Text(event['message'] as String),
                  subtitle: Text(event['occurred_at'] as String),
                  leading: Icon(Icons.circle, size: 10, color: _colorFor(context, event['level'] as String)),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
