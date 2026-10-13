import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/models/book.dart';

/// books 表访问。
class BookDao {
  BookDao(this._db);

  final Database _db;

  Future<void> insert(Book book) async {
    await _db.insert('books', book.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String bookId) async {
    await _db.delete('books', where: 'id = ?', whereArgs: <Object?>[bookId]);
  }

  Future<List<Book>> findAll() async {
    final List<Map<String, Object?>> rows = await _db.query('books', orderBy: 'updated_at DESC');
    return rows.map(Book.fromRow).toList();
  }

  Future<Book?> findById(String bookId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'books',
      where: 'id = ?',
      whereArgs: <Object?>[bookId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Book.fromRow(rows.first);
  }
}
