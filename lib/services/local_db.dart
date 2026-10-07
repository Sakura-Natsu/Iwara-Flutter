import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 本地数据库：播放进度、搜索历史。
class LocalDb {
  LocalDb._(this._db);

  final Database _db;
  static LocalDb? _instance;
  static LocalDb get instance => _instance!;

  static Future<void> init() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'iwara.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE progress(
            video_id TEXT PRIMARY KEY,
            position_ms INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE search_history(
            query TEXT NOT NULL,
            type TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(query, type)
          )''');
      },
    );
    _instance = LocalDb._(db);
  }

  // ---------------- 播放进度 ----------------

  Future<void> saveProgress(String videoId, Duration position, Duration duration) {
    return _db.insert(
      'progress',
      {
        'video_id': videoId,
        'position_ms': position.inMilliseconds,
        'duration_ms': duration.inMilliseconds,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<(Duration, Duration)?> progress(String videoId) async {
    final rows = await _db.query('progress',
        where: 'video_id = ?', whereArgs: [videoId], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      Duration(milliseconds: r['position_ms'] as int),
      Duration(milliseconds: r['duration_ms'] as int),
    );
  }

  Future<void> clearProgress(String videoId) =>
      _db.delete('progress', where: 'video_id = ?', whereArgs: [videoId]);

  // ---------------- 搜索历史 ----------------

  Future<void> addSearch(String query, String type) => _db.insert(
        'search_history',
        {
          'query': query,
          'type': type,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<String>> searchHistory({int limit = 20}) async {
    final rows = await _db.rawQuery(
        'SELECT query, MAX(updated_at) t FROM search_history GROUP BY query ORDER BY t DESC LIMIT ?',
        [limit]);
    return rows.map((r) => r['query'] as String).toList();
  }

  Future<void> removeSearch(String query) =>
      _db.delete('search_history', where: 'query = ?', whereArgs: [query]);

  Future<void> clearSearchHistory() => _db.delete('search_history');
}
