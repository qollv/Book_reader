import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/data/dao/book_dao.dart';
import 'package:novel_reader/data/repositories/annotation_repository.dart';
import 'package:novel_reader/data/repositories/reader_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/bookmark.dart';
import 'package:novel_reader/models/chapter.dart';
import 'package:novel_reader/models/note.dart';
import 'package:novel_reader/models/reading_progress.dart';

/// 阅读器状态：开书、翻页、重排版、书签、笔记。
///
/// 进度以「章 + 段 + 行」锚点持久化，字号行距变化重排版后仍能回到原位。
class ReaderController extends ChangeNotifier {
  ReaderController({
    required ReaderRepository readerRepository,
    required AnnotationRepository annotationRepository,
    required BookDao bookDao,
  }) : _readerRepository = readerRepository,
       _annotationRepository = annotationRepository,
       _bookDao = bookDao;

  final ReaderRepository _readerRepository;
  final AnnotationRepository _annotationRepository;
  final BookDao _bookDao;

  Book? _book;
  List<Chapter> _chapters = <Chapter>[];
  List<ParagraphBlock> _blocks = <ParagraphBlock>[];
  List<ReaderPage> _pages = <ReaderPage>[const ReaderPage(index: 0, lines: <PageLine>[])];
  List<Bookmark> _bookmarks = <Bookmark>[];
  List<ReadingNote> _notes = <ReadingNote>[];

  int _chapterIndex = 0;
  int _pageIndex = 0;
  bool _isLoading = false;
  String? _error;
  Timer? _progressTimer;

  Book? get book => _book;
  List<Chapter> get chapters => _chapters;
  List<ReaderPage> get pages => _pages;
  List<Bookmark> get bookmarks => _bookmarks;
  List<ReadingNote> get notes => _notes;
  int get chapterIndex => _chapterIndex;
  int get pageIndex => _pageIndex;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ReaderPage? get currentPage =>
      _pageIndex >= 0 && _pageIndex < _pages.length ? _pages[_pageIndex] : null;

  /// 全书阅读百分比：已读完章节 + 当前章内页进度。
  double get bookPercent {
    if (_chapters.isEmpty) {
      return 0;
    }
    final double chapterPart = _chapterIndex / _chapters.length;
    final double pagePart = _pages.isEmpty ? 0 : _pageIndex / _pages.length / _chapters.length;
    return (chapterPart + pagePart).clamp(0.0, 1.0);
  }

  bool get isBookmarked {
    final ReaderPage? page = currentPage;
    if (page == null || page.lines.isEmpty) {
      return false;
    }
    final PageLine first = page.lines.first;
    for (Bookmark bookmark in _bookmarks) {
      if (bookmark.chapterIndex == _chapterIndex &&
          bookmark.paragraphIndex == first.paragraphIndex &&
          bookmark.lineIndex == first.lineIndex) {
        return true;
      }
    }
    return false;
  }

  Future<void> openBook(String bookId) async {
    _isLoading = true;
    _error = null;
    // 先清空上一本书的状态，避免打开失败时残留旧内容
    _book = null;
    _chapters = <Chapter>[];
    _blocks = <ParagraphBlock>[];
    _pages = <ReaderPage>[const ReaderPage(index: 0, lines: <PageLine>[])];
    _chapterIndex = 0;
    _pageIndex = 0;
    notifyListeners();
    try {
      final Book? book = await _bookDao.findById(bookId);
      if (book == null) {
        _error = '书籍不存在或已被删除';
        return;
      }
      _book = book;
      _chapters = await _readerRepository.loadChapters(bookId);
      await _refreshAnnotations();

      final ReadingProgress? progress = await _readerRepository.loadProgress(bookId);
      if (progress != null && progress.chapterIndex < _chapters.length) {
        await _openChapter(progress.chapterIndex, anchor: progress);
      } else {
        await _openChapter(0, anchor: null);
      }
    } catch (error) {
      // 失败时连已赋值的新书引用一起清掉，避免残留半开状态
      _book = null;
      _chapters = <Chapter>[];
      _blocks = <ParagraphBlock>[];
      _pages = <ReaderPage>[const ReaderPage(index: 0, lines: <PageLine>[])];
      _chapterIndex = 0;
      _pageIndex = 0;
      _error = '打开失败：${error is ImportException ? error.message : error}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 外观参数变化后重新分页，并尽量保持当前锚点不动。
  Future<void> repaginate(PaginationConfig config) async {
    if (_book == null) {
      return;
    }
    final ReaderPage? oldPage = currentPage;
    _pages = await _readerRepository.getPages(
      bookId: _book!.id,
      chapterIndex: _chapterIndex,
      blocks: _blocks,
      config: config,
    );
    if (oldPage != null && oldPage.lines.isNotEmpty) {
      _pageIndex = findPageForAnchor(_pages, oldPage.lines.first.paragraphIndex, oldPage.lines.first.lineIndex);
    }
    notifyListeners();
  }

  Future<void> goToPage(int index) async {
    if (index < 0 || index >= _pages.length) {
      return;
    }
    _pageIndex = index;
    notifyListeners();
    _schedulePersistProgress();
  }

  Future<void> nextChapter() async {
    if (_chapterIndex + 1 < _chapters.length) {
      await _openChapter(_chapterIndex + 1, anchor: null);
    }
  }

  Future<void> previousChapter() async {
    if (_chapterIndex > 0) {
      await _openChapter(_chapterIndex - 1, anchor: null);
    }
  }

  /// 目录跳转：打开指定章节（回到章首）。
  Future<void> openChapter(int index) async {
    await _openChapter(index, anchor: null);
  }

  /// 翻到书签/笔记锚点所在位置。
  Future<void> jumpTo({required int chapterIndex, required int paragraphIndex, required int lineIndex}) async {
    if (chapterIndex != _chapterIndex) {
      await _openChapter(chapterIndex, anchor: ReadingProgress(
        bookId: _book?.id ?? '',
        chapterIndex: chapterIndex,
        paragraphIndex: paragraphIndex,
        lineIndex: lineIndex,
        percent: bookPercent,
        updatedAt: 0,
      ));
      return;
    }
    _pageIndex = findPageForAnchor(_pages, paragraphIndex, lineIndex);
    notifyListeners();
    _schedulePersistProgress();
  }

  Future<void> toggleBookmark() async {
    final ReaderPage? page = currentPage;
    if (_book == null || page == null || page.lines.isEmpty) {
      return;
    }
    final PageLine first = page.lines.first;
    if (isBookmarked) {
      for (Bookmark bookmark in _bookmarks) {
        if (bookmark.chapterIndex == _chapterIndex &&
            bookmark.paragraphIndex == first.paragraphIndex &&
            bookmark.lineIndex == first.lineIndex) {
          await _annotationRepository.deleteBookmark(bookmark.id);
        }
      }
    } else {
      final int now = DateTime.now().millisecondsSinceEpoch;
      await _annotationRepository.addBookmark(Bookmark(
        id: const Uuid().v4(),
        bookId: _book!.id,
        chapterIndex: _chapterIndex,
        paragraphIndex: first.paragraphIndex,
        lineIndex: first.lineIndex,
        chapterTitle: _chapters[_chapterIndex].title,
        excerpt: first.text,
        comment: '',
        createdAt: now,
        updatedAt: now,
      ));
    }
    await _refreshAnnotations();
  }

  Future<void> addNote(String selectedText, String content) async {
    final ReaderPage? page = currentPage;
    if (_book == null || page == null || page.lines.isEmpty) {
      return;
    }
    final PageLine first = page.lines.first;
    final int now = DateTime.now().millisecondsSinceEpoch;
    await _annotationRepository.addNote(ReadingNote(
      id: const Uuid().v4(),
      bookId: _book!.id,
      chapterIndex: _chapterIndex,
      paragraphIndex: first.paragraphIndex,
      lineIndex: first.lineIndex,
      chapterTitle: _chapters[_chapterIndex].title,
      selectedText: selectedText,
      content: content,
      createdAt: now,
      updatedAt: now,
    ));
    await _refreshAnnotations();
  }

  Future<void> updateNote(String noteId, String content) async {
    for (ReadingNote note in _notes) {
      if (note.id == noteId) {
        await _annotationRepository.updateNote(note.copyWith(
          content: content,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }
    await _refreshAnnotations();
  }

  Future<void> deleteNote(String noteId) async {
    await _annotationRepository.deleteNote(noteId);
    await _refreshAnnotations();
  }

  /// 书签列表页的删除入口。
  Future<void> deleteBookmark(String bookmarkId) async {
    await _annotationRepository.deleteBookmark(bookmarkId);
    await _refreshAnnotations();
  }

  Future<void> _openChapter(int index, {ReadingProgress? anchor}) async {
    if (_book == null || index < 0 || index >= _chapters.length) {
      return;
    }
    _chapterIndex = index;
    _blocks = await _readerRepository.loadChapterBlocks(_book!.contentPath, _chapters[index]);
    _pages = <ReaderPage>[];
    _pageIndex = 0;
    notifyListeners();

    await repaginate(_pendingConfig ?? _defaultConfig());
    if (anchor != null) {
      _pageIndex = findPageForAnchor(_pages, anchor.paragraphIndex, anchor.lineIndex);
      notifyListeners();
    }
    // 切章是自然的落库点：取消挂起的防抖，立即写一次
    _progressTimer?.cancel();
    _progressTimer = null;
    await _persistProgress();
  }

  // 重排版所需配置由 UI 层（知道屏幕尺寸）在打开章节前注入
  PaginationConfig? _pendingConfig;

  void provideConfig(PaginationConfig config) {
    _pendingConfig = config;
  }

  PaginationConfig _defaultConfig() {
    return const PaginationConfig(
      fontSize: 18,
      lineHeight: 1.8,
      pageWidth: 360,
      pageHeight: 720,
      horizontalMargin: 24,
      verticalMargin: 20,
    );
  }

  Future<void> _refreshAnnotations() async {
    if (_book == null) {
      return;
    }
    _bookmarks = await _annotationRepository.listBookmarks(_book!.id);
    _notes = await _annotationRepository.listNotes(_book!.id);
    notifyListeners();
  }

  /// 进度写库防抖：连续翻页/拖滑块只保留最后一次，300ms 后落库。
  void _schedulePersistProgress() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 300), () {
      _progressTimer = null;
      _persistProgress();
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _persistProgress(); // 退出阅读器前把最后位置写掉
    super.dispose();
  }

  Future<void> _persistProgress() async {
    if (_book == null) {
      return;
    }
    final ReaderPage? page = currentPage;
    final PageLine first = page != null && page.lines.isNotEmpty
        ? page.lines.first
        : const PageLine(text: '', paragraphIndex: 0, lineIndex: 0, isFirstLineOfParagraph: true, kind: ParagraphKind.paragraph, headingLevel: 1);
    await _readerRepository.saveProgress(ReadingProgress(
      bookId: _book!.id,
      chapterIndex: _chapterIndex,
      paragraphIndex: first.paragraphIndex,
      lineIndex: first.lineIndex,
      percent: bookPercent,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }
}
