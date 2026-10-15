import 'package:flutter/material.dart';

import 'package:novel_reader/core/parsers/book_file_guard.dart';
import 'package:novel_reader/core/text/byte_text_decoder.dart';
import 'package:novel_reader/data/dao/book_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/data/repositories/book_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/reading_progress.dart';
import 'package:novel_reader/services/import/book_importer.dart';
import 'package:novel_reader/services/import/local_file_importer.dart';

/// 书籍 + 进度 的合并视图，书架列表直接用。
class BookshelfItem {
  const BookshelfItem({required this.book, required this.progress});

  final Book book;
  final ReadingProgress? progress;

  double get percent => progress?.percent ?? 0;
}

/// 书架状态：列表加载、导入（本地/URL）、删书。
class BookshelfController extends ChangeNotifier {
  BookshelfController({
    required BookDao bookDao,
    required ProgressDao progressDao,
    required BookRepository bookRepository,
    required BookImporter importer,
  }) : _bookDao = bookDao,
       _progressDao = progressDao,
       _bookRepository = bookRepository,
       _importer = importer;

  final BookDao _bookDao;
  final ProgressDao _progressDao;
  final BookRepository _bookRepository;
  final BookImporter _importer;

  List<BookshelfItem> _items = <BookshelfItem>[];
  bool _isImporting = false;
  double _importFraction = 0;
  String? _importError;

  List<BookshelfItem> get items => _items;
  bool get isImporting => _isImporting;
  double get importFraction => _importFraction;
  String? get importError => _importError;

  Future<void> load() async {
    final List<Book> books = await _bookDao.findAll();
    final List<BookshelfItem> items = <BookshelfItem>[];
    for (Book book in books) {
      final ReadingProgress? progress = await _progressDao.findByBook(book.id);
      items.add(BookshelfItem(book: book, progress: progress));
    }
    _items = items;
    notifyListeners();
  }

  /// 本地文件导入；用户取消时静默返回。
  Future<Book?> importLocal() async {
    _isImporting = true;
    _importError = null;
    _importFraction = 0;
    notifyListeners();
    try {
      final Book? book = await _importer.pickLocal();
      if (book != null) {
        await load();
      }
      return book;
    } catch (error) {
      _importError = _friendlyError(error);
      return null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<Book?> importFromUrl(String url) async {
    _isImporting = true;
    _importError = null;
    _importFraction = 0;
    notifyListeners();
    try {
      final Book book = await _importer.fromUrl(
        url,
        onProgress: (int received, int total) {
          if (total > 0) {
            _importFraction = received / total;
            notifyListeners();
          }
        },
      );
      await load();
      return book;
    } catch (error) {
      _importError = _friendlyError(error);
      return null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  /// 导入异常带中文可读信息，其余异常按原样展示。
  ///
  /// 解析/编码层抛出的异常都是「可以直接给用户看的一句话」，
  /// 这里显式识别它们，而不是碰巧依赖 `toString()` 恰好返回了中文——
  /// 否则改动其中一个类的 toString 就会让用户看到内部类型名。
  String _friendlyError(Object error) {
    if (error is ImportException) {
      return error.message;
    }
    if (error is BookFileRejected) {
      return error.message;
    }
    if (error is TextDecodeException) {
      return error.message;
    }
    return error.toString();
  }

  Future<void> deleteBook(String bookId) async {
    await _bookRepository.deleteBook(bookId);
    await load();
  }

  void clearError() {
    _importError = null;
    notifyListeners();
  }
}
