import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/data/dao/book_dao.dart';
import 'package:novel_reader/data/dao/bookmark_dao.dart';
import 'package:novel_reader/data/dao/chapter_cache_dao.dart';
import 'package:novel_reader/data/dao/chapter_dao.dart';
import 'package:novel_reader/data/dao/note_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/data/dao/source_dao.dart';
import 'package:novel_reader/data/repositories/annotation_repository.dart';
import 'package:novel_reader/data/repositories/book_repository.dart';
import 'package:novel_reader/data/repositories/online_book_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/services/source/source_registry.dart';

import '../support/fake_http_fetcher.dart';
import '../support/test_database.dart';

/// 带搜索/详情/目录/正文的完整测试源声明。
String fullManifest() => jsonEncode(<String, Object?>{
      'id': 'test.online',
      'name': '在线测试源',
      'apiVersion': 4,
      'baseUrl': 'https://ex.com',
      'charset': 'utf-8',
      'capabilities': <String>['search', 'bookInfo', 'volumes', 'chapter'],
      'bookInfo': <String, Object?>{
        'path': '/book/{id}',
        'fields': <String, String>{
          'title': '#info h1',
          'author': '#info .author|replace:作者：,',
          'cover': '#info img.cover@src',
        },
      },
      'volumes': <String, Object?>{
        'path': '/book/{id}',
        'volumes': '.volume',
        'volumeTitle': '.volume-title',
        'chapters': 'li a',
        'chapterFields': <String, String>{'id': '@href|regex:/read/(\\d+)'},
      },
      'chapter': <String, Object?>{
        'path': '/read/{chapterId}',
        'content': '#content p',
        'next': '#next@href|regex:/read/(\\d+)',
      },
      'search': <String, Object?>{
        'types': <Map<String, Object?>>[
          <String, Object?>{'id': 'name', 'name': '书名', 'path': '/search?q={q}&page={page}'},
        ],
        'list': '.book-item',
        'fields': <String, String>{'title': 'h3 a', 'id': 'h3 a@href|regex:(\\d+)'},
      },
    });

String chapterHtml(String title, {String? nextId}) {
  return '<html><body>'
      '<h1 id="title">$title</h1>'
      '<div id="content"><p>　　$title 的第一段。</p><p>　　第二段。</p></div>'
      '${nextId == null ? '' : '<a id="next" href="/read/$nextId">下一章</a>'}'
      '</body></html>';
}

void main() {
  late Database db;
  late FakeHttpFetcher fetcher;
  late SourceRegistry registry;
  late ChapterCacheDao cacheDao;
  late BookRepository bookRepository;
  late OnlineBookRepository repository;
  late Directory supportDir;

  setUp(() async {
    db = await openTestDatabase();
    fetcher = FakeHttpFetcher();
    registry = SourceRegistry(dao: SourceDao(db), fetcher: fetcher);
    await registry.load();
    await registry.install(fullManifest());

    cacheDao = ChapterCacheDao(db);
    supportDir = await Directory.systemTemp.createTemp('novel_reader_online');
    bookRepository = BookRepository(
      bookDao: BookDao(db),
      chapterDao: ChapterDao(db),
      progressDao: ProgressDao(db),
      annotationRepository: AnnotationRepository(
        bookmarkDao: BookmarkDao(db),
        noteDao: NoteDao(db),
      ),
      supportDirectory: () async => supportDir,
    );

    repository = OnlineBookRepository(
      registry: registry,
      cacheDao: cacheDao,
      bookRepository: bookRepository,
    );

    fetcher.route('/read/1001', chapterHtml('第一章 锈迹', nextId: '1002'));
    fetcher.route('/read/1002', chapterHtml('第二章 回声', nextId: '1003'));
    fetcher.route('/read/1003', chapterHtml('第三章 出港'));
  });

  tearDown(() async {
    await registry.dispose();
    await db.close();
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
  });

  group('本地优先双发射', () {
    /// 直接往数据库缓存里塞一章，模拟「上次读过 / 上次导入过」的状态。
    ///
    /// 必须绕过 CachedHttp（它有内存 TTL 缓存），否则测出来的不是
    /// 「离线读」而是「HTTP 层缓存命中」，看起来很对但什么都没验证到。
    Future<void> seedCache(String chapterId, {String text = '缓存里的旧内容'}) async {
      await cacheDao.put(
        sourceId: 'test.online',
        bookId: '101',
        content: SourceChapterContent(
          id: chapterId,
          title: '缓存标题',
          blocks: <ParagraphBlock>[
            ParagraphBlock(text: text, kind: ParagraphKind.paragraph),
          ],
        ),
      );
    }

    test('没有缓存时只发一次网络结果', () async {
      final List<SourceChapterContent> emitted = await repository
          .chapterStream(sourceId: 'test.online', bookId: '101', chapterId: '1001')
          .toList();

      expect(emitted.length, 1);
      expect(emitted.single.blocks.first.text, contains('第一章 锈迹'));
    });

    test('有缓存时先发缓存再发网络结果，后者覆盖前者', () async {
      await seedCache('1001');
      fetcher.route('/read/1001', chapterHtml('网络上的新内容', nextId: '1002'));

      final List<SourceChapterContent> emitted = await repository
          .chapterStream(sourceId: 'test.online', bookId: '101', chapterId: '1001')
          .toList();

      expect(emitted.length, 2, reason: '第一次是本地缓存，第二次是网络');
      expect(emitted.first.blocks.first.text, '缓存里的旧内容');
      expect(emitted.last.blocks.first.text, contains('网络上的新内容'));

      // 网络结果写穿缓存
      final SourceChapterContent? cached = await cacheDao.find(
        sourceId: 'test.online',
        bookId: '101',
        chapterId: '1001',
      );
      expect(cached!.blocks.first.text, contains('网络上的新内容'));
    });

    test('网络不可达但已有缓存 → 静默离线读，不抛异常', () async {
      await seedCache('1001');
      fetcher.offline = true;

      final List<SourceChapterContent> emitted = await repository
          .chapterStream(sourceId: 'test.online', bookId: '101', chapterId: '1001')
          .toList();

      expect(emitted.length, 1, reason: '只发缓存，网络那一次静默失败');
      expect(emitted.single.blocks.first.text, '缓存里的旧内容');
      expect(registry.entryOf('test.online')!.error, isNotEmpty, reason: '故障要留痕');
    });

    test('无缓存又不可达 → 抛 network 错误并记录', () async {
      fetcher.offline = true;

      await expectLater(
        repository
            .chapterStream(sourceId: 'test.online', bookId: '101', chapterId: '9999')
            .toList(),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.kind, 'kind', SourceErrorKind.network)),
      );
      expect(registry.entryOf('test.online')!.error, isNotEmpty);
    });

    test('refresh 同时绕过数据库缓存与 HTTP 缓存', () async {
      await seedCache('1001');
      fetcher.route('/read/1001', chapterHtml('刷新后的内容', nextId: '1002'));
      // 先正常读一次，把 HTTP 缓存也捂热
      await repository
          .chapterStream(sourceId: 'test.online', bookId: '101', chapterId: '1001')
          .toList();
      fetcher.route('/read/1001', chapterHtml('再次刷新后的内容', nextId: '1002'));
      final int before = fetcher.requests.length;

      final List<SourceChapterContent> emitted = await repository
          .chapterStream(
              sourceId: 'test.online', bookId: '101', chapterId: '1001', refresh: true)
          .toList();

      expect(emitted.length, 1, reason: 'refresh 时不该先吐缓存');
      expect(emitted.single.blocks.first.text, contains('再次刷新后的内容'));
      expect(fetcher.requests.length, before + 1, reason: 'HTTP 缓存也必须被绕过');
    });
  });

  group('缓存', () {
    test('fetchChapter 写穿缓存', () async {
      expect(await repository.cachedChapterCount('test.online', '101'), 0);
      await repository.fetchChapter(
          sourceId: 'test.online', bookId: '101', chapterId: '1001');
      expect(await repository.cachedChapterCount('test.online', '101'), 1);
    });

    test('按书聚合占用', () async {
      for (final String id in <String>['1001', '1002', '1003']) {
        await repository.fetchChapter(
            sourceId: 'test.online', bookId: '101', chapterId: id);
      }

      final usage = await cacheDao.usageByBook();
      expect(usage.length, 1);
      expect(usage.single.bookId, '101');
      expect(usage.single.chapters, 3);
      expect(usage.single.bytes, greaterThan(0));
      expect(await cacheDao.totalBytes(), greaterThan(0));
    });

    test('未入库的书对应的缓存被识别为孤儿（可清理）', () async {
      await fetcher.routeFile('/book/101', 'test/fixtures/book.html');
      await repository.fetchChapter(
          sourceId: 'test.online', bookId: '101', chapterId: '1001');
      expect(await cacheDao.orphanCount(), 1);

      await repository.importToShelf(
        book: const SourceBook(
            sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
      );
      expect(await cacheDao.orphanCount(), 0, reason: '书入库后缓存不再算孤儿');
    });
  });

  group('整本导入书架', () {
    Future<void> routeBook() async {
      await fetcher.routeFile('/book/101', 'test/fixtures/book.html');
    }

    test('抓完整本后落盘并可像本地书一样阅读', () async {
      await routeBook();
      final List<String> progress = <String>[];

      final Book book = await repository.importToShelf(
        book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
        onProgress: (int fetched, int total, String title) {
          progress.add('$fetched/$total $title');
        },
      );

      expect(book.title, '星海拾遗');
      expect(book.author, '林间');
      expect(book.format, 'online');
      expect(book.sourceId, 'test.online');
      expect(book.sourceBookId, '101');
      expect(book.coverUrl, 'https://ex.com/cover/101.jpg');
      expect(book.chapterCount, 3);
      expect(progress.length, 3);
      expect(progress.last, startsWith('3/3'));

      // content.jsonl 与本地导入同构：一段一行 JSON
      final File contentFile = File(book.contentPath);
      expect(await contentFile.exists(), isTrue);
      final List<String> lines = (await contentFile.readAsString())
          .split('\n')
          .where((String l) => l.trim().isNotEmpty)
          .toList();
      // 每章 = 1 个标题段 + 2 个正文段
      expect(lines.length, 9);
      final Map<String, Object?> firstBlock =
          jsonDecode(lines.first) as Map<String, Object?>;
      expect(firstBlock['text'], '第一章 锈迹');
      expect(firstBlock['kind'], 'heading');

      // chapters 表按段落区间记录
      final List<Map<String, Object?>> chapters = await db.query(
        'chapters',
        where: 'book_id = ?',
        whereArgs: <Object?>[book.id],
        orderBy: 'chapter_index ASC',
      );
      expect(chapters.length, 3);
      expect(chapters.first['title'], '第一章 锈迹');
      expect(chapters.first['paragraph_start'], 0);
      expect(chapters.first['paragraph_end'], 3);
    });

    test('重复导入复用同一个本地 bookId（进度/书签不丢）', () async {
      await routeBook();
      final Book first = await repository.importToShelf(
        book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
      );
      final Book second = await repository.importToShelf(
        book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
      );

      expect(second.id, first.id);
      final List<Map<String, Object?>> books = await db.query('books');
      expect(books.length, 1, reason: '同一 (源, 源内 id) 只应有一本');
    });

    test('findOnShelf 能命中已导入的书', () async {
      await routeBook();
      expect(await repository.findOnShelf('test.online', '101'), isNull);

      final Book book = await repository.importToShelf(
        book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
      );

      expect((await repository.findOnShelf('test.online', '101'))?.id, book.id);
    });

    test('抓取中途失败不会留下半本书', () async {
      await routeBook();
      fetcher.route('/read/1003', '<html><body><div id="content"></div></body></html>');

      await expectLater(
        repository.importToShelf(
          book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
        ),
        throwsA(isA<SourceError>()),
      );

      expect(await db.query('books'), isEmpty, reason: '全量抓完才落盘');
      expect(await db.query('chapters'), isEmpty);
    });

    test('取消导入时抛 cancelled', () async {
      await routeBook();
      int calls = 0;

      await expectLater(
        repository.importToShelf(
          book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
          shouldContinue: () async => calls++ == 0,
        ),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.kind, 'kind', SourceErrorKind.cancelled)),
      );
      expect(await db.query('books'), isEmpty);
    });

    test('目录为空时明确报错', () async {
      fetcher.route('/book/101', '<html><body><div id="info"><h1>空书</h1></div></body></html>');

      await expectLater(
        repository.importToShelf(
          book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '空书'),
        ),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.kind, 'kind', SourceErrorKind.parse)),
      );
    });

    test('章数超过上限时拒绝，避免误抓整站', () async {
      await routeBook();
      await expectLater(
        repository.importToShelf(
          book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
          maxChapters: 2,
        ),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.kind, 'kind', SourceErrorKind.invalid)),
      );
    });

    test('导入过程会把章节写进缓存（下次离线可读）', () async {
      await routeBook();
      await repository.importToShelf(
        book: const SourceBook(sourceId: 'test.online', bookId: '101', title: '星海拾遗'),
      );
      expect(await repository.cachedChapterCount('test.online', '101'), 3);
    });
  });

  group('源不可用时的可读错误', () {
    test('源被停用时给出明确原因', () async {
      await registry.setEnabled('test.online', false);

      await expectLater(
        repository
            .chapterStream(sourceId: 'test.online', bookId: '101', chapterId: '1001')
            .toList(),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.kind, 'kind', SourceErrorKind.unsupported)
            .having((SourceError e) => e.message, 'message', contains('停用'))),
      );
    });

    test('源不存在时给出明确原因', () async {
      await expectLater(
        repository
            .chapterStream(sourceId: 'nope', bookId: '1', chapterId: '1')
            .toList(),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.message, 'message', contains('不存在'))),
      );
    });
  });
}
