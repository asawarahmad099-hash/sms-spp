import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sms_gateway/services/local_db.dart';

/// sqflite's real plugin only works via platform channels on a device;
/// sqflite_common_ffi provides an in-memory SQLite engine so this queue
/// logic is verifiable in a plain `flutter test` run, off-device.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;

  setUp(() async {
    // Fresh in-memory DB per test — LocalDb is a singleton, so reset its
    // cached handle and point sqflite at a unique in-memory path each time.
    databaseFactory = databaseFactoryFfiNoIsolate;
    db = LocalDb.instance;
    await db.database; // opens (or reuses) the singleton connection

    // Clear both tables rather than reopening, since LocalDb caches its
    // Database handle as a singleton by design (mirrors production usage).
    final conn = await db.database;
    await conn.delete('queue');
    await conn.delete('event_log');
  });

  test('enqueues a leased message and can remove it once reported', () async {
    await db.enqueueLeased(
      messageId: 'msg-1',
      recipientMsisdn: '+15550001111',
      body: 'hello',
      simSlotIndex: 0,
      leaseExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      attemptNumber: 1,
    );

    expect(await db.queueDepth(), 1);

    await db.removeFromQueue('msg-1');

    expect(await db.queueDepth(), 0);
  });

  test('marks a message sent_pending_report and it shows up in pendingReports()', () async {
    await db.enqueueLeased(
      messageId: 'msg-2',
      recipientMsisdn: '+15550002222',
      body: 'hi',
      simSlotIndex: 1,
      leaseExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      attemptNumber: 1,
    );

    await db.markSentPendingReport('msg-2');

    final pending = await db.pendingReports();
    expect(pending, hasLength(1));
    expect(pending.first['message_id'], 'msg-2');
    expect(pending.first['state'], 'sent_pending_report');
  });

  test('identifies a stale unsent lease as safe to drop', () async {
    await db.enqueueLeased(
      messageId: 'msg-3',
      recipientMsisdn: '+15550003333',
      body: 'stale',
      simSlotIndex: 0,
      leaseExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      attemptNumber: 1,
    );

    final stale = await db.staleUnsent();
    expect(stale, hasLength(1));
    expect(stale.first['message_id'], 'msg-3');
  });

  test('does not flag a sent_pending_report row as stale-unsent, even past its lease window', () async {
    await db.enqueueLeased(
      messageId: 'msg-4',
      recipientMsisdn: '+15550004444',
      body: 'sent already',
      simSlotIndex: 0,
      leaseExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      attemptNumber: 1,
    );
    await db.markSentPendingReport('msg-4');

    expect(await db.staleUnsent(), isEmpty);
  });

  test('bounds the event log to eventLogCap most recent rows', () async {
    for (var i = 0; i < LocalDb.eventLogCap + 10; i++) {
      await db.log('info', 'event $i');
    }

    final events = await db.recentEvents(limit: LocalDb.eventLogCap + 50);
    expect(events.length, LocalDb.eventLogCap);
    // Most recent first, and the earliest ones were pruned.
    expect(events.first['message'], 'event ${LocalDb.eventLogCap + 9}');
  });
}
