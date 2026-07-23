import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalLocationStore {
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'exercise_tracker.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE location_points(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
      },
    );
    return _db!;
  }

  Future<void> insertPoint(Map<String, Object?> point) async {
    final database = await db;
    await database.insert('location_points', point, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> pending({int limit = 20}) async {
    final database = await db;
    return database.query(
      'location_points',
      where: 'sync_status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'sequence_number ASC',
      limit: limit,
    );
  }

  Future<int> pendingCount() async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT COUNT(*) AS count FROM location_points WHERE sync_status = 'PENDING'",
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> totalCount() async {
    final database = await db;
    final rows = await database.rawQuery('SELECT COUNT(*) AS count FROM location_points');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<void> markSynced(List<int> sequences) async {
    if (sequences.isEmpty) return;
    final database = await db;
    final placeholders = List.filled(sequences.length, '?').join(',');
    await database.rawUpdate(
      'UPDATE location_points SET sync_status = ? WHERE sequence_number IN ($placeholders)',
      ['SYNCED', ...sequences],
    );
  }
}
