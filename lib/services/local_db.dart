import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Durable local state so a crash or a dropped network connection can never
/// silently lose track of a message that was already leased — and, more
/// importantly, never lose track of one that was already *sent* before the
/// app could confirm the report call went through.
///
/// `queue` holds leased-but-not-yet-reported messages. A row moves from
/// `leased` to `sent_pending_report` the instant the native send call
/// returns (success or failure) — deliberately *before* the report HTTP
/// call is attempted — so that if the app dies right there, the next loop
/// iteration finds a `sent_pending_report` row and retries the *report*
/// call, never a re-send.
class LocalDb {
  LocalDb._();

  static final LocalDb instance = LocalDb._();

  Database? _db;

  static const eventLogCap = 500;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'sms_gateway.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE queue (
            message_id TEXT PRIMARY KEY,
            recipient_msisdn TEXT NOT NULL,
            body TEXT NOT NULL,
            sim_slot_index INTEGER,
            lease_expires_at TEXT NOT NULL,
            state TEXT NOT NULL,
            attempt_number INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE event_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            occurred_at TEXT NOT NULL,
            level TEXT NOT NULL,
            message TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // --- queue ---------------------------------------------------------

  Future<void> enqueueLeased({
    required String messageId,
    required String recipientMsisdn,
    required String body,
    required int? simSlotIndex,
    required DateTime leaseExpiresAt,
    required int attemptNumber,
  }) async {
    final db = await database;

    await db.insert(
      'queue',
      {
        'message_id': messageId,
        'recipient_msisdn': recipientMsisdn,
        'body': body,
        'sim_slot_index': simSlotIndex,
        'lease_expires_at': leaseExpiresAt.toIso8601String(),
        'state': 'leased',
        'attempt_number': attemptNumber,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markSentPendingReport(String messageId) async {
    final db = await database;

    await db.update(
      'queue',
      {'state': 'sent_pending_report'},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> removeFromQueue(String messageId) async {
    final db = await database;

    await db.delete('queue', where: 'message_id = ?', whereArgs: [messageId]);
  }

  Future<List<Map<String, Object?>>> pendingReports() async {
    final db = await database;

    return db.query('queue', where: 'state = ?', whereArgs: ['sent_pending_report']);
  }

  /// Rows whose lease the server has certainly already reclaimed
  /// (RETRY_WAIT/expired) because they're still `leased` locally — never
  /// sent — well past their lease window. Safe to drop; nothing to report.
  Future<List<Map<String, Object?>>> staleUnsent() async {
    final db = await database;
    final cutoff = DateTime.now().toIso8601String();

    return db.query(
      'queue',
      where: 'state = ? AND lease_expires_at < ?',
      whereArgs: ['leased', cutoff],
    );
  }

  Future<int> queueDepth() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM queue');

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // --- event log -------------------------------------------------------

  Future<void> log(String level, String message) async {
    final db = await database;

    await db.insert('event_log', {
      'occurred_at': DateTime.now().toIso8601String(),
      'level': level,
      'message': message,
    });

    await db.rawDelete('''
      DELETE FROM event_log WHERE id NOT IN (
        SELECT id FROM event_log ORDER BY id DESC LIMIT $eventLogCap
      )
    ''');
  }

  Future<List<Map<String, Object?>>> recentEvents({int limit = 100}) async {
    final db = await database;

    return db.query('event_log', orderBy: 'id DESC', limit: limit);
  }
}
