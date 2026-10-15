import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/data/dao/chapter_cache_dao.dart';
import 'package:novel_reader/data/repositories/book_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/services/source/source_registry.dart';

/// 在线数据源的读路径与入库路径。
///
/// 核心策略来自上游 `BookRepository`：**本地优先双发射**——
/// 先发本地缓存，再发网络结果，网络成功则「写穿」缓存；
/// 网络失败时若已有缓存就静默降级为离线读，绝不因为网络
/// 把用户正在看的章节变成错误页。
class OnlineBookRepository {
  OnlineBookRepository({
    required SourceRegistry registry,
    required ChapterCacheDao cacheDao,
    required BookRepository bookRepository,
  })  : _registry = registry,
        _cacheDao = cacheDao,
        _bookRepository = bookRepository;

  final SourceRegistry _registry;
  final ChapterCacheDao _cacheDao;
  final BookRepository _bookRepository;

  /// 默认单本导入上限，避免用户误点把整站抓下来。
  static const int maxImportChapters = 3000;

  SourceEngine engineFor(String sourceId) {
    final SourceEngine? engine = _registry.engineFor(sourceId);
    if (engine == null) {
      final SourceEntry? entry = _registry.entryOf(sourceId);
      final String reason = switch (entry?.status) {
        SourceStatus.disabled => '数据源已停用',
        SourceStatus.incompatible => entry?.error ?? '数据源与本版本不兼容',
        SourceStatus.error => entry?.error ?? '数据源加载失败',
        _ => '数据源不存在',
      };
      throw SourceError(SourceErrorKind.unsupported, reason);
    }
    return engine;
  }

  /// 章节正文的**本地优先双发射**流。
  ///
  /// 调用方可以只取 `first`（离线优先，最快出内容）或取 `last`（拿最新）。
  Stream<SourceChapterContent> chapterStream({
    required String sourceId,
    required String bookId,
    required String chapterId,
    bool refresh = false,
  }) async* {
    final SourceChapterContent? cached = await _cacheDao.find(
      sourceId: sourceId,
      bookId: bookId,
      chapterId: chapterId,
    );
    if (cached != null && !refresh) {
      yield cached;
    }

    final SourceEngine engine = engineFor(sourceId);
    try {
      final SourceChapterContent fresh = await engine.chapterContent(
        chapterId,
        bookId: bookId,
        refresh: refresh,
      );
      await _cacheDao.put(sourceId: sourceId, bookId: bookId, content: fresh);
      yield fresh;
    } on SourceError catch (e) {
      if (cached != null) {
        // 有缓存就离线读，把网络故障吞掉——只记一次源错误供 UI 提示
        await _registry.markError(sourceId, e.message);
        return;
      }
      await _registry.markError(sourceId, e.message);
      rethrow;
    }
  }

  /// 只走网络（导入时用，避免对每章都走一遍缓存查询）。
  Future<SourceChapterContent> fetchChapter({
    required String sourceId,
    required String bookId,
    required String chapterId,
  }) async {
    final SourceChapterContent content =
        await engineFor(sourceId).chapterContent(chapterId, bookId: bookId);
    await _cacheDao.put(sourceId: sourceId, bookId: bookId, content: content);
    return content;
  }

  Future<SourceBookDetail> bookDetail(String sourceId, String bookId) {
    return engineFor(sourceId).bookDetail(bookId);
  }

  Future<List<SourceBook>> explore(
    String sourceId,
    String exploreId, {
    Map<String, String> filterChoices = const <String, String>{},
    Map<String, double> filterSliders = const <String, double>{},
    Map<String, bool> filterToggles = const <String, bool>{},
    int page = 1,
  }) {
    return engineFor(sourceId).explore(
      exploreId,
      filterChoices: filterChoices,
      filterSliders: filterSliders,
      filterToggles: filterToggles,
      page: page,
    );
  }

  Stream<SourceSearchEvent> search(
    String sourceId,
    String typeId,
    String keyword, {
    int maxPages = 1,
  }) {
    try {
      return engineFor(sourceId).search(typeId, keyword, maxPages: maxPages);
    } on SourceError catch (e) {
      return Stream<SourceSearchEvent>.value(SourceSearchEvent.error(e.message));
    }
  }

  /// 这本书是否已经在书架里（按源 + 源内 id 去重）。
  Future<Book?> findOnShelf(String sourceId, String sourceBookId) {
    return _bookRepository.findBySource(sourceId, sourceBookId);
  }

  /// 缓存了多少章 / 一共多少章。
  Future<int> cachedChapterCount(String sourceId, String bookId) {
    return _cacheDao.countByBook(sourceId, bookId);
  }

  /// 把源里的一本书整本抓下来并放进书架。
  ///
  /// 先全部抓到内存里的 [ParsedChapter] 列表，再一次性落盘：
  /// 抓取中途失败不会在书架上留下半本书。同一本书重复导入时
  /// 复用已有的本地 bookId，于是阅读进度/书签不会丢。
  Future<Book> importToShelf({
    required SourceBook book,
    void Function(int fetched, int total, String chapterTitle)? onProgress,
    Future<bool> Function()? shouldContinue,
    int maxChapters = maxImportChapters,
  }) async {
    final SourceEngine engine = engineFor(book.sourceId);
    final SourceBookDetail detail = await engine.bookDetail(book.bookId);
    final List<SourceChapter> chapters = detail.chapters;
    if (chapters.isEmpty) {
      throw const SourceError(SourceErrorKind.parse, '这本书的目录是空的');
    }
    if (chapters.length > maxChapters) {
      throw SourceError(
        SourceErrorKind.invalid,
        '章节数 ${chapters.length} 超过上限 $maxChapters',
      );
    }

    final List<ParsedChapter> parsed = <ParsedChapter>[];
    int fetched = 0;
    for (final SourceChapter chapter in chapters) {
      if (shouldContinue != null && !await shouldContinue()) {
        throw const SourceError(SourceErrorKind.cancelled, '导入已取消');
      }
      final SourceChapterContent content = await fetchChapter(
        sourceId: book.sourceId,
        bookId: book.bookId,
        chapterId: chapter.id,
      );
      final String title =
          content.title.isNotEmpty ? content.title : chapter.title;
      parsed.add(ParsedChapter(
        title: title,
        // 章节标题作为一段 heading 写进正文，阅读器里就能看到章名，
        // 与本地 md/txt 解析出的标题行为一致
        blocks: <ParagraphBlock>[
          ParagraphBlock(text: title, kind: ParagraphKind.heading),
          ...content.blocks,
        ],
      ));
      fetched++;
      onProgress?.call(fetched, chapters.length, title);
    }

    final Book? existing = await _bookRepository.findBySource(book.sourceId, book.bookId);
    return _bookRepository.importBlocks(
      title: detail.book.title.isNotEmpty ? detail.book.title : book.title,
      author: detail.book.author.isNotEmpty ? detail.book.author : book.author,
      format: 'online',
      chapters: parsed,
      sourceId: book.sourceId,
      sourceBookId: book.bookId,
      coverUrl: detail.book.coverUrl.isNotEmpty ? detail.book.coverUrl : book.coverUrl,
      bookId: existing?.id, // 已有则原地替换，保留进度/书签
    );
  }
}
