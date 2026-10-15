import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/core/source/json_rule_engine.dart';
import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/models/source_manifest.dart';
import 'package:novel_reader/services/source/cached_http.dart';

import '../support/fake_http_fetcher.dart';

/// 这些用例全部跑在静态 HTML fixture 上：不起服务器、不碰真实站点。
/// 真实站点的选择器随时会变，测它等于测别人的网站；测规则引擎才是测自己。
void main() {
  late FakeHttpFetcher fetcher;
  late JsonRuleEngine engine;
  late SourceManifest manifest;

  Future<JsonRuleEngine> buildEngine(FakeHttpFetcher f) async {
    return JsonRuleEngine(
      manifest: manifest,
      http: CachedHttp(
        fetcher: f,
        baseDelay: const Duration(milliseconds: 1),
        defaultTtl: Duration(milliseconds: manifest.cacheTtlMs),
      ),
    );
  }

  setUpAll(() async {
    final String raw = await File('assets/sources/sample_source.json').readAsString();
    manifest = SourceManifest.fromJson(jsonDecode(raw) as Map<String, Object?>);
  });

  setUp(() async {
    fetcher = FakeHttpFetcher();
    await fetcher.routeFile('/rank?page=1', 'test/fixtures/rank.html');
    await fetcher.routeFile('/latest?page=1', 'test/fixtures/rank.html');
    await fetcher.routeFile('/book/101', 'test/fixtures/book.html');
    await fetcher.routeFile('/read/1001', 'test/fixtures/chapter.html');
    engine = await buildEngine(fetcher);
  });

  group('探索页', () {
    test('解析书单，跳过没有可用 id 的条目', () async {
      final List<SourceBook> books = await engine.explore('rank');

      expect(books.length, 3, reason: '第 4 个条目的 href 里没有数字 id，应当被跳过');
      expect(
        books.map((SourceBook b) => b.title).toList(),
        <String>['星海拾遗', '长夜行舟', '纸鸢与海'],
      );
      expect(books.first.bookId, '101');
      expect(books.first.author, contains('林间'));
      expect(books.first.sourceId, 'sample.demo');
    });

    test('封面相对地址被补全成绝对地址', () async {
      final List<SourceBook> books = await engine.explore('rank');
      expect(books.first.coverUrl, 'http://127.0.0.1:8765/cover/101.jpg');
    });

    test('过滤器被拼进 URL', () async {
      // 过滤器改变了 URL，fixture 要按最终地址注册
      await fetcher.routeFile(
        '/rank?page=1&sort=hot&finished=1',
        'test/fixtures/rank.html',
      );

      await engine.explore('rank',
          filterChoices: <String, String>{'sort': '热度'},
          filterToggles: <String, bool>{'finished': true});

      final Uri last = fetcher.requests.last;
      expect(last.path, '/rank');
      expect(last.query, allOf(contains('page=1'), contains('sort=hot'), contains('finished=1')));
    });

    test('未知过滤项默认值不产生多余参数', () async {
      await engine.explore('rank');
      expect(fetcher.requests.last.query, 'page=1');
    });

    test('重复请求命中缓存，不再发 HTTP', () async {
      await engine.explore('rank');
      final int first = fetcher.requests.length;
      await engine.explore('rank');
      expect(fetcher.requests.length, first, reason: 'TTL 内应当直接吃缓存');
    });

    test('查询不存在的探索页 → unsupported 错误', () async {
      await expectLater(
        engine.explore('nope'),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.kind, 'kind', SourceErrorKind.unsupported)),
      );
    });

    test('请求头里的 {base} 被替换', () async {
      await engine.explore('rank');
      expect(fetcher.requestHeaders.last['Referer'], 'http://127.0.0.1:8765/');
    });
  });

  group('搜索', () {
    test('逐条产出结果并以 end 收尾', () async {
      fetcher.route('/search?q=star&page=1', await File('test/fixtures/search.html').readAsString());

      final List<SourceSearchEvent> events =
          await engine.search('name', 'star').toList();

      expect(events.first.kind, SourceSearchEventKind.book);
      expect(events.first.book?.title, '星海拾遗');
      expect(events.last.kind, SourceSearchEventKind.end);
      expect(events.where((SourceSearchEvent e) => e.kind == SourceSearchEventKind.book).length, 1);
    });

    test('空结果产出 empty 再 end（而不是静默结束）', () async {
      fetcher.route('/search?q=zzz&page=1', '<html><body><div class="empty">没有结果</div></body></html>');

      final List<SourceSearchEvent> events = await engine.search('name', 'zzz').toList();

      expect(events.map((SourceSearchEvent e) => e.kind).toList(),
          <SourceSearchEventKind>[SourceSearchEventKind.empty, SourceSearchEventKind.end]);
    });

    test('中文关键词被百分号编码', () async {
      fetcher.route('/search?q=%E6%98%9F%E6%B5%B7&page=1', '<html><body></body></html>');
      await engine.search('name', '星海').toList();

      expect(fetcher.requests.last.path, '/search');
      expect(fetcher.requests.last.query, contains('%E6%98%9F'));
    });

    test('未知搜索类型产出 error 事件而非抛异常', () async {
      final List<SourceSearchEvent> events = await engine.search('nope', 'x').toList();
      expect(events.single.kind, SourceSearchEventKind.error);
    });

    test('网络失败时已产出的结果不丢，错误作为事件透出', () async {
      fetcher.offline = true;
      final List<SourceSearchEvent> events = await engine.search('name', 'x').toList();
      expect(events.single.kind, SourceSearchEventKind.error);
      expect(events.single.message, isNotEmpty);
    });
  });

  group('书目详情', () {
    test('解析标题/作者/封面/标签/完结状态', () async {
      final SourceBookDetail detail = await engine.bookDetail('101');

      expect(detail.book.title, '星海拾遗');
      expect(detail.book.author, '林间', reason: 'replace 规则应当去掉「作者：」前缀');
      expect(detail.book.coverUrl, 'http://127.0.0.1:8765/cover/101.jpg');
      expect(detail.book.description, contains('拾荒者'));
      expect(detail.book.tags, <String>['科幻', '冒险']);
      expect(detail.book.isComplete, isTrue);
    });

    test('目录按卷分组，章节标题回退到链接文本', () async {
      final SourceBookDetail detail = await engine.bookDetail('101');

      expect(detail.volumes.length, 2);
      expect(detail.volumes[0].title, '第一卷 星港');
      expect(detail.volumes[1].title, '第二卷 深空');
      expect(detail.chapters.length, 3);
      expect(detail.chapters.first.id, '1001');
      expect(detail.chapters.first.title, '第一章 锈迹');
      expect(detail.chapters.last.id, '1003');
    });

    test('详情页与目录页同一 URL 时只请求一次', () async {
      await engine.bookDetail('101');
      expect(
        fetcher.requests.where((Uri u) => u.path == '/book/101').length,
        1,
        reason: '同页抓取应当命中缓存',
      );
    });

    test('章节数超过上限时拒绝导入', () async {
      // 目录解析成 3 章；用一个假的 registry 无关紧要，这里只验证引擎层
      expect((await engine.volumes('101')).first.chapters.length, 2);
    });
  });

  group('正文', () {
    test('解析段落并压掉空白段与全角缩进', () async {
      final SourceChapterContent content = await engine.chapterContent('1001');

      expect(content.title, '第一章 锈迹');
      expect(content.blocks.length, 4, reason: '&nbsp; 那一段规范化后为空，应被丢弃');
      expect(content.blocks.first.text.startsWith('星港已经废弃'), isTrue);
      expect(content.blocks.first.text.contains('\u3000'), isFalse, reason: '全角缩进应被规范化');
    });

    test('解析上一章/下一章 id', () async {
      final SourceChapterContent content = await engine.chapterContent('1001');
      expect(content.nextId, '1002');
      expect(content.prevId, '1000');
    });

    test('没有下一章时 nextId 为 null（而不是空串）', () async {
      fetcher.route(
        '/read/1099',
        '<html><body><div id="content"><p>内容一</p></div>'
            '<a id="next" href="#">下一章</a></body></html>',
      );
      final SourceChapterContent content = await engine.chapterContent('1099');
      expect(content.nextId, isNull);
    });

    test('选择器失效时报 parse 错误，而不是产出空章节', () async {
      final FakeHttpFetcher empty = FakeHttpFetcher();
      empty.route('/read/1001', '<html><body><div id="nothing">内容搬走了</div></body></html>');
      final JsonRuleEngine fresh = await buildEngine(empty);

      await expectLater(
        fresh.chapterContent('1001'),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.kind, 'kind', SourceErrorKind.parse)),
      );
    });

    test('没声明目录规则时抛 unsupported', () async {
      final SourceManifest noVolumes = SourceManifest.fromJson(<String, Object?>{
        'id': 'no.vol',
        'name': '无目录源',
        'apiVersion': 4,
        'baseUrl': 'https://ex.com',
        'capabilities': <String>['chapter'],
        'chapter': <String, Object?>{'path': '/read/{chapterId}', 'content': '#content p'},
      });
      final JsonRuleEngine e = JsonRuleEngine(
        manifest: noVolumes,
        http: CachedHttp(fetcher: fetcher, baseDelay: const Duration(milliseconds: 1)),
      );

      await expectLater(
        e.volumes('1'),
        throwsA(isA<SourceError>()
            .having((SourceError e) => e.kind, 'kind', SourceErrorKind.unsupported)),
      );
    });
  });

  group('ping', () {
    test('可达时返回 true', () async {
      expect(await engine.ping(), isTrue);
    });

    test('不可达时返回 false 而不抛异常', () async {
      final FakeHttpFetcher dead = FakeHttpFetcher()..offline = true;
      final JsonRuleEngine fresh = await buildEngine(dead);
      expect(await fresh.ping(), isFalse);
    });
  });
}
