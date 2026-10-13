import 'package:novel_reader/data/dao/bookmark_dao.dart';
import 'package:novel_reader/data/dao/note_dao.dart';
import 'package:novel_reader/models/bookmark.dart';
import 'package:novel_reader/models/note.dart';

/// 书签与笔记的统一入口。
class AnnotationRepository {
  AnnotationRepository({required BookmarkDao bookmarkDao, required NoteDao noteDao})
      : _bookmarkDao = bookmarkDao,
        _noteDao = noteDao;

  final BookmarkDao _bookmarkDao;
  final NoteDao _noteDao;

  Future<void> addBookmark(Bookmark bookmark) {
    return _bookmarkDao.insert(bookmark);
  }

  Future<void> deleteBookmark(String bookmarkId) {
    return _bookmarkDao.delete(bookmarkId);
  }

  Future<List<Bookmark>> listBookmarks(String bookId) {
    return _bookmarkDao.findByBook(bookId);
  }

  Future<List<Bookmark>> allBookmarks() {
    return _bookmarkDao.findAll();
  }

  Future<void> addNote(ReadingNote note) {
    return _noteDao.insert(note);
  }

  Future<void> updateNote(ReadingNote note) {
    return _noteDao.update(note);
  }

  Future<void> deleteNote(String noteId) {
    return _noteDao.delete(noteId);
  }

  Future<List<ReadingNote>> listNotes(String bookId) {
    return _noteDao.findByBook(bookId);
  }

  Future<List<ReadingNote>> allNotes() {
    return _noteDao.findAll();
  }

  Future<void> deleteByBook(String bookId) async {
    await _bookmarkDao.deleteByBook(bookId);
    await _noteDao.deleteByBook(bookId);
  }
}
