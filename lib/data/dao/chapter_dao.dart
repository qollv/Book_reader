import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/models/chapter.dart';

/// chapters 表访问。
class ChapterDao {
  ChapterDao(this._db);

  final Database _db;

  Future<void> replaceAll(String bookId, List<Chapter> chapters) async {
    final Batch batch = _db.batch();
    batch.delete('chapters', where: 'book_id = ?', whereArgs: <Object?>[bookId]);
    for (Chapter chapter in chapters) {
      batch.insert('chapters', chapter.toRow());
    }
    await batch.commit(noResult: true);
  }

  Future<List<Chapter>> findByBook(String bookId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'chapters',
      where: 'book_id = ?',
      whereArgs: <Object?>[bookId],
      orderBy: 'chapter_index ASC',
    );
    return rows.map(Chapter.fromRow).toList();
  }
}
