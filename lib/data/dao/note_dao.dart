import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/models/note.dart';

/// notes 表访问。
class NoteDao {
  NoteDao(this._db);

  final Database _db;

  Future<void> insert(ReadingNote note) async {
    await _db.insert('notes', note.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(ReadingNote note) async {
    await _db.update(
      'notes',
      note.toRow(),
      where: 'id = ?',
      whereArgs: <Object?>[note.id],
    );
  }

  Future<void> delete(String noteId) async {
    await _db.delete('notes', where: 'id = ?', whereArgs: <Object?>[noteId]);
  }

  Future<void> deleteByBook(String bookId) async {
    await _db.delete('notes', where: 'book_id = ?', whereArgs: <Object?>[bookId]);
  }

  Future<List<ReadingNote>> findByBook(String bookId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'notes',
      where: 'book_id = ?',
      whereArgs: <Object?>[bookId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(ReadingNote.fromRow).toList();
  }

  Future<List<ReadingNote>> findAll() async {
    final List<Map<String, Object?>> rows = await _db.query('notes');
    return rows.map(ReadingNote.fromRow).toList();
  }
}
