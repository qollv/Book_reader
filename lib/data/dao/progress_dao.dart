import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/models/reading_progress.dart';

/// progress 表访问（每本书一行）。
class ProgressDao {
  ProgressDao(this._db);

  final Database _db;

  Future<void> upsert(ReadingProgress progress) async {
    await _db.insert(
      'progress',
      progress.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ReadingProgress?> findByBook(String bookId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'progress',
      where: 'book_id = ?',
      whereArgs: <Object?>[bookId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ReadingProgress.fromRow(rows.first);
  }

  Future<void> deleteByBook(String bookId) async {
    await _db.delete('progress', where: 'book_id = ?', whereArgs: <Object?>[bookId]);
  }

  Future<List<ReadingProgress>> findAll() async {
    final List<Map<String, Object?>> rows = await _db.query('progress');
    return rows.map(ReadingProgress.fromRow).toList();
  }
}
