import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/models/bookmark.dart';

/// bookmarks 表访问。
class BookmarkDao {
  BookmarkDao(this._db);

  final Database _db;

  Future<void> insert(Bookmark bookmark) async {
    await _db.insert('bookmarks', bookmark.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String bookmarkId) async {
    await _db.delete('bookmarks', where: 'id = ?', whereArgs: <Object?>[bookmarkId]);
  }

  Future<void> deleteByBook(String bookId) async {
    await _db.delete('bookmarks', where: 'book_id = ?', whereArgs: <Object?>[bookId]);
  }

  Future<List<Bookmark>> findByBook(String bookId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: <Object?>[bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Bookmark.fromRow).toList();
  }

  Future<List<Bookmark>> findAll() async {
    final List<Map<String, Object?>> rows = await _db.query('bookmarks');
    return rows.map(Bookmark.fromRow).toList();
  }
}
