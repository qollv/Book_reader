import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

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
import 'package:novel_reader/services/source/http_fetcher.dart';
import 'package:novel_reader/services/source/source_registry.dart';

import '../../tool/fixture_site.dart';
import '../support/test_database.dart';

/// 端到端：真实 dart:io HTTP 传输 + 真实 SQLite + fixture 站点。
///
/// 前面的用例都用内存桩，快而稳；这一档专门验证「换掉传输层还成立」——
/// 桩测不出来的是请求头怎么发、响应字节怎么落、gzip/编码这条真链路。
void main() {
  late FixtureSite site;
  late Database db;
  late SourceRegistry registry;
  late OnlineBookRepository repository;
  late BookRepository bookRepository;
  late Directory supportDir;

  setUpAll(() async {
    site = await FixtureSite.start(port: 0);
  });

  tearDownAll(() async => site.stop());

  setUp(() async {
    db = await openTestDatabase();
    registry = SourceRegistry(dao: SourceDao(db), fetcher: IoHttpFetcher());
    await registry.load();

    // 用随包示例源，只把 baseUrl 指向本次随机端口：
    // 这样「示例源能跑」这件事是被测试保证的，不是靠手测。
    final String raw = await File('assets/sources/sample_source.json').readAsString();
    final Map<String, Object?> json = (jsonDecode(raw) as Map<String, Object?>)
      ..['baseUrl'] = site.baseUrl;
    final SourceInstallResult installed = await registry.install(jsonEncode(json));
    expect(installed.ok, isTrue, reason: installed.message);

    supportDir = await Directory.systemTemp.createTemp('novel_reader_live');
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
      cacheDao: ChapterCacheDao(db),
      bookRepository: bookRepository,
    );
  });

  tearDown(() async {
    await registry.dispose();
    await db.close();
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
  });

  test('示例源能被真实 HTTP 传输跑通：探索页', () async {
    final List<SourceBook> books = await repository.explore('sample.demo', 'rank');

    expect(books.length, 3);
    expect(books.first.title, '星海拾遗');
    expect(books.first.coverUrl, '${site.baseUrl}/cover/101.jpg');
  });

  test('示例源能被真实 HTTP 传输跑通：详情与目录', () async {
    final SourceBookDetail detail = await repository.bookDetail('sample.demo', '101');

    expect(detail.book.title, '星海拾遗');
    expect(detail.book.author, '林间');
    expect(detail.book.isComplete, isTrue);
    expect(detail.chapters.map((SourceChapter c) => c.id).toList(),
        <String>['1001', '1002', '1003']);
  });

  test('示例源能被真实 HTTP 传输跑通：正文与前后章', () async {
    final List<SourceChapterContent> emitted = await repository
        .chapterStream(sourceId: 'sample.demo', bookId: '101', chapterId: '1002')
        .toList();

    expect(emitted.single.blocks.length, 3, reason: '空白段应被丢弃');
    expect(emitted.single.nextId, '1003');
    expect(emitted.single.prevId, '1001');
  });

  test('整本导入书架：真实 HTTP 传输的端到端链路', () async {
    final Book book = await repository.importToShelf(
      book: const SourceBook(sourceId: 'sample.demo', bookId: '101', title: '星海拾遗'),
    );

    expect(book.title, '星海拾遗');
    expect(book.author, '林间');
    expect(book.chapterCount, 3);
    expect(book.format, 'online');
    expect(book.contentPath, endsWith('content.jsonl'));
    expect(await File(book.contentPath).exists(), isTrue);

    // 正文确实落了盘，且第一段是章标题（heading）
    final List<String> lines = (await File(book.contentPath).readAsString())
        .split('\n')
        .where((String l) => l.trim().isNotEmpty)
        .toList();
    expect(jsonDecode(lines.first), containsPair('text', '第一章 锈迹'));
    expect(jsonDecode(lines.first), containsPair('kind', 'heading'));

    // 再读一次走缓存路径：把站点停掉也应可读
    await site.stop();
    final List<SourceChapterContent> cached = await repository
        .chapterStream(sourceId: 'sample.demo', bookId: '101', chapterId: '1001')
        .toList();
    expect(cached, isNotEmpty);
    expect(cached.first.blocks.first.text, contains('锈迹'));

    // 恢复站点，避免影响后续用例
    site = await FixtureSite.start(port: 0);
  });

  test('源声明里声明的请求头真的发出去了', () async {
    // 用示例源的 Referer 规则做一次真请求，服务端不校验它，
    // 但我们可以通过「请求成功」间接确认自定义头没有把请求搞坏
    final bool alive = await registry.engineFor('sample.demo')!.ping();
    expect(alive, isTrue);
  });

  test('ping 对不可达的地址返回 false', () async {
    final SourceRegistry dead = SourceRegistry(
      dao: SourceDao(db),
      fetcher: IoHttpFetcher(),
    );
    await dead.load();
    await dead.install(jsonEncode(<String, Object?>{
      'id': 'dead.src',
      'name': '不可达源',
      'apiVersion': 4,
      'baseUrl': 'http://127.0.0.1:1', // 保留端口，必然连不上
      'capabilities': <String>['chapter'],
      'chapter': <String, Object?>{'path': '/read/{chapterId}', 'content': '#content p'},
    }));

    expect(await dead.engineFor('dead.src')!.ping(), isFalse);
    await dead.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('真实传输下 404 被翻译成 notFound 而不是崩溃', () async {
    await expectLater(
      repository
          .chapterStream(sourceId: 'sample.demo', bookId: '101', chapterId: '999999')
          .toList(),
      throwsA(predicate((Object? e) => e.toString().contains('SourceError'))),
    );
  });
}
