import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalLocationStore {
  LocalLocationStore({required this.userId, required this.deviceSessionId});

  final String userId;
  final String deviceSessionId;
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'exercise_tracker.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE location_points(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            device_session_id TEXT NOT NULL,
            sequence_number INTEGER NOT NULL UNIQUE,
            captured_at TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy REAL,
            speed REAL,
            heading REAL,
            sync_status TEXT NOT NULL DEFAULT 'PENDING'
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_location_points_exercise_id '
          'ON location_points(exercise_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          // Unknown legacy ownership stays NULL and is never uploaded as another user.
          await db.execute('ALTER TABLE location_points ADD COLUMN user_id TEXT');
          await db.execute('ALTER TABLE location_points ADD COLUMN device_session_id TEXT');
        }
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE location_points ADD COLUMN exercise_id TEXT');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_location_points_exercise_id '
            'ON location_points(exercise_id)',
          );
        }
      },
    );
    return _db!;
  }

  Future<void> insertPoint(Map<String, Object?> point) async {
    final database = await db;
    await database.insert('location_points', {...point, 'user_id': userId, 'device_session_id': deviceSessionId},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> pending({
    required String exerciseId,
    int limit = 20,
  }) async {
    final database = await db;
    return database.query(
      'location_points',
      where: 'exercise_id = ? AND user_id = ? AND device_session_id = ? AND sync_status = ?',
      whereArgs: [exerciseId, userId, deviceSessionId, 'PENDING'],
      orderBy: 'sequence_number ASC',
      limit: limit,
    );
  }

  Future<int> pendingCount(String exerciseId) async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT COUNT(*) AS count FROM location_points "
      "WHERE exercise_id = ? AND user_id = ? AND device_session_id = ? AND sync_status = 'PENDING'",
      [exerciseId, userId, deviceSessionId],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> totalCount(String exerciseId) async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM location_points WHERE exercise_id = ? AND user_id = ? AND device_session_id = ?',
      [exerciseId, userId, deviceSessionId],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<void> markSynced(String exerciseId, List<int> sequences) async {
    if (sequences.isEmpty) return;
    final database = await db;
    final placeholders = List.filled(sequences.length, '?').join(',');
    await database.rawUpdate(
      'UPDATE location_points SET sync_status = ? '
      'WHERE exercise_id = ? AND user_id = ? AND device_session_id = ? AND sequence_number IN ($placeholders)',
      ['SYNCED', exerciseId, userId, deviceSessionId, ...sequences],
    );
  }
}
