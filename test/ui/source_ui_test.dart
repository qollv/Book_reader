import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

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
import 'package:novel_reader/data/repositories/reader_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/services/source/source_registry.dart';
import 'package:novel_reader/state/explore_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/source_controller.dart';
import 'package:novel_reader/ui/pages/explore_page.dart';
import 'package:novel_reader/ui/pages/source_manager_page.dart';
import 'package:novel_reader/ui/theme/reading_palettes.dart';
import 'package:novel_reader/ui/widgets/source_book_sheet.dart';

import '../support/fake_http_fetcher.dart';
import '../support/test_database.dart';

/// 界面层冒烟测试：用内存桩 + 内存库把新页面真的渲染一遍。
///
/// 只测「接得上、显示得出、出错有提示」，不测像素——像素级断言在样式迭代时
/// 维护成本远高于它发现问题的价值。
///
/// 注意一个容易踩的坑：`testWidgets` 的测试体跑在假异步区里，**真实 I/O 不会
/// 被推进**。数据库、资源读取这类调用必须放进 `tester.runAsync`，否则 await
/// 会永久挂起（表现为整个测试文件卡死）。所以下面凡是碰 DB/资源的调用都包了一层。
void main() {
  late Database db;
  late FakeHttpFetcher fetcher;
  late SourceRegistry registry;
  late SourceController sourceController;
  late ExploreController exploreController;
  late ReaderController readerController;

  String manifest() => jsonEncode(<String, Object?>{
        'id': 'ui.test',
        'name': '界面测试源',
        'apiVersion': 4,
        'baseUrl': 'https://ex.com',
        'charset': 'utf-8',
        'capabilities': <String>['search', 'explore', 'bookInfo', 'volumes', 'chapter'],
        'explore': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'rank',
            'title': '排行榜',
            'path': '/rank?page={page}{extra}',
            'list': '.book-item',
            'fields': <String, String>{
              'title': 'h3 a',
              'id': 'h3 a@href|regex:(\\d+)',
              'author': '.author',
            },
            'filters': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'single',
                'key': 'sort',
                'title': '排序',
                'choices': <String, String>{'默认': '', '热度': '&sort=hot'},
              },
            ],
          },
        ],
        'search': <String, Object?>{
          'types': <Map<String, Object?>>[
            <String, Object?>{'id': 'name', 'name': '书名', 'path': '/search?q={q}&page={page}'},
          ],
          'list': '.book-item',
          'fields': <String, String>{'title': 'h3 a', 'id': 'h3 a@href|regex:(\\d+)'},
        },
        'bookInfo': <String, Object?>{
          'path': '/book/{id}',
          'fields': <String, String>{'title': '#info h1', 'author': '#info .author'},
        },
        'volumes': <String, Object?>{
          'path': '/book/{id}',
          'chapters': 'li a',
          'chapterFields': <String, String>{'id': '@href|regex:/read/(\\d+)'},
        },
        'chapter': <String, Object?>{
          'path': '/read/{chapterId}',
          'content': '#content p',
        },
      });

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<SourceController>.value(value: sourceController),
        ChangeNotifierProvider<ExploreController>.value(value: exploreController),
        ChangeNotifierProvider<ReaderController>.value(value: readerController),
      ],
      child: MaterialApp(
        home: child,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown)),
      ),
    );
  }

  /// 在真实异步区里装源，绕开假异步区。
  Future<void> installSource(WidgetTester tester, {String? json}) async {
    await tester.runAsync(() async {
      final SourceInstallResult result =
          await sourceController.install(json ?? manifest());
      expect(result.ok, isTrue, reason: result.message);
    });
  }

  setUp(() async {
    db = await openTestDatabase();
    fetcher = FakeHttpFetcher();
    registry = SourceRegistry(dao: SourceDao(db), fetcher: fetcher);
    await registry.load();

    final AnnotationRepository annotations = AnnotationRepository(
      bookmarkDao: BookmarkDao(db),
      noteDao: NoteDao(db),
    );
    final BookRepository bookRepository = BookRepository(
      bookDao: BookDao(db),
      chapterDao: ChapterDao(db),
      progressDao: ProgressDao(db),
      annotationRepository: annotations,
    );

    sourceController = SourceController(registry: registry);
    exploreController = ExploreController(
      registry: registry,
      repository: OnlineBookRepository(
        registry: registry,
        cacheDao: ChapterCacheDao(db),
        bookRepository: bookRepository,
      ),
    );
    readerController = ReaderController(
      readerRepository: ReaderRepository(
        chapterDao: ChapterDao(db),
        progressDao: ProgressDao(db),
      ),
      annotationRepository: annotations,
      bookDao: BookDao(db),
    );

    await sourceController.load();
  });

  tearDown(() async {
    await registry.dispose();
    await db.close();
  });

  group('探索页', () {
    testWidgets('没有数据源时显示引导而不是空白', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const ExplorePage()));
      await tester.pumpAndSettle();

      expect(find.text('还没有可用的数据源'), findsOneWidget);
      expect(find.text('安装内置示例源'), findsOneWidget);
      expect(find.text('打开数据源管理'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('内置示例源能装上（顺带验证资源已正确打包）', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const ExplorePage()));
      await tester.pumpAndSettle();
      expect(find.text('安装内置示例源'), findsOneWidget);

      // 读资源是真实 I/O，必须放进 runAsync
      late SourceInstallResult result;
      await tester.runAsync(() async {
        result = await sourceController.installSample();
      });
      await tester.pumpAndSettle();

      expect(result.ok, isTrue, reason: result.message);
      expect(sourceController.entries.any((SourceEntry e) => e.id == 'sample.demo'), isTrue);
      expect(sourceController.hasUsableSource, isTrue);
      expect(find.text('示例源（本地 fixture）'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('装上源后渲染探索列表', (WidgetTester tester) async {
      await installSource(tester);
      fetcher.route('/rank?page=1', '''
        <div class="book-item"><h3><a href="/book/101">星海拾遗</a></h3>
          <span class="author">林间</span></div>
        <div class="book-item"><h3><a href="/book/102">长夜行舟</a></h3>
          <span class="author">渡口</span></div>
      ''');

      await tester.pumpWidget(wrap(const ExplorePage()));
      await tester.pumpAndSettle();

      expect(find.text('界面测试源'), findsOneWidget);
      expect(find.text('排行榜'), findsOneWidget);
      expect(find.text('星海拾遗'), findsOneWidget);
      expect(find.text('长夜行舟'), findsOneWidget);
      expect(find.text('林间'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('加载失败时显示错误与重试按钮', (WidgetTester tester) async {
      await installSource(tester);
      fetcher.offline = true;

      await tester.pumpWidget(wrap(const ExplorePage()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('过滤器切换会带上参数重新请求', (WidgetTester tester) async {
      await installSource(tester);
      fetcher.route(
          '/rank?page=1', '<div class="book-item"><h3><a href="/book/101">甲书</a></h3></div>');
      fetcher.route('/rank?page=1&sort=hot',
          '<div class="book-item"><h3><a href="/book/103">乙书</a></h3></div>');

      await tester.pumpWidget(wrap(const ExplorePage()));
      await tester.pumpAndSettle();
      expect(find.text('甲书'), findsOneWidget);

      await tester.tap(find.text('热度'));
      await tester.pumpAndSettle();

      expect(fetcher.requests.last.query, contains('sort=hot'));
      expect(find.text('乙书'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('点击列表项会弹出详情面板', (WidgetTester tester) async {
      await installSource(tester);
      fetcher.route(
          '/rank?page=1', '<div class="book-item"><h3><a href="/book/101">星海拾遗</a></h3></div>');

      await tester.pumpWidget(wrap(const ExplorePage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('星海拾遗'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 只断言「面板被拉起」：它内部要读数据库查书架状态，
      // 那属于真实 I/O，不该在这里等——面板本身的渲染由下面单独的用例覆盖
      expect(find.byType(SourceBookSheet), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('详情面板', () {
    /// 用假回调直接渲染面板：不碰数据库、不碰网络，于是完全确定。
    Widget sheet({
      Book? onShelf,
      SourceBookDetail? detail,
      Object? detailError,
      Future<Book> Function(
        void Function(int, int, String)? onProgress,
        Future<bool> Function()? shouldContinue,
      )? importBook,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SourceBookSheet(
            book: const SourceBook(
              sourceId: 'ui.test',
              bookId: '101',
              title: '星海拾遗',
              author: '林间',
              description: '一名拾荒者在废弃星港里捡到了不该捡的东西。',
              tags: <String>['科幻', '冒险'],
            ),
            loadShelfState: () async => onShelf,
            loadDetail: () async {
              if (detailError != null) {
                throw SourceError(SourceErrorKind.network, '$detailError');
              }
              return detail ??
                  const SourceBookDetail(
                    book: SourceBook(
                        sourceId: 'ui.test', bookId: '101', title: '星海拾遗', author: '林间'),
                    volumes: <SourceVolume>[
                      SourceVolume(title: '', chapters: <SourceChapter>[
                        SourceChapter(id: '1', title: '第一章'),
                        SourceChapter(id: '2', title: '第二章'),
                      ]),
                    ],
                  );
            },
            importBook: importBook ??
                (
                  void Function(int, int, String)? onProgress,
                  Future<bool> Function()? shouldContinue,
                ) async =>
                    const Book(
                      id: 'local-1',
                      title: '星海拾遗',
                      author: '林间',
                      format: 'online',
                      contentPath: '/tmp/x.jsonl',
                      chapterCount: 2,
                      totalChars: 10,
                      fileSize: 1,
                      createdAt: 0,
                      updatedAt: 0,
                    ),
            onOpenBook: (_) {},
          ),
        ),
      );
    }

    testWidgets('未入库时显示「加入书架并下载」与章数', (WidgetTester tester) async {
      await tester.pumpWidget(sheet());
      await tester.pumpAndSettle();

      expect(find.text('星海拾遗'), findsWidgets);
      expect(find.text('林间'), findsOneWidget);
      expect(find.textContaining('共 2 章'), findsOneWidget);
      expect(find.text('科幻'), findsOneWidget);
      expect(find.text('加入书架并下载'), findsOneWidget);
      expect(find.text('阅读'), findsNothing);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('已在书架时出现「阅读」按钮', (WidgetTester tester) async {
      await tester.pumpWidget(sheet(
        onShelf: const Book(
          id: 'local-1',
          title: '星海拾遗',
          author: '林间',
          format: 'online',
          contentPath: '/tmp/x.jsonl',
          chapterCount: 2,
          totalChars: 10,
          fileSize: 1,
          createdAt: 0,
          updatedAt: 0,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('更新本地副本'), findsOneWidget);
      expect(find.text('阅读'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('详情失败仍可导入，并提示原因', (WidgetTester tester) async {
      await tester.pumpWidget(sheet(detailError: '连接超时'));
      await tester.pumpAndSettle();

      expect(find.textContaining('详情读取失败'), findsOneWidget);
      expect(find.textContaining('连接超时'), findsOneWidget);
      expect(find.text('加入书架并下载'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('导入过程显示进度，完成后回调打开书籍', (WidgetTester tester) async {
      Book? opened;
      final Completer<void> gate = Completer<void>();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SourceBookSheet(
            book: const SourceBook(
                sourceId: 'ui.test', bookId: '101', title: '星海拾遗'),
            loadShelfState: () async => null,
            loadDetail: () async => throw const SourceError(SourceErrorKind.parse, '不测详情'),
            importBook: (
              void Function(int, int, String)? onProgress,
              Future<bool> Function()? shouldContinue,
            ) async {
              onProgress?.call(1, 3, '第一章');
              await gate.future;
              onProgress?.call(3, 3, '第三章');
              return const Book(
                id: 'local-1',
                title: '星海拾遗',
                author: '林间',
                format: 'online',
                contentPath: '/tmp/x.jsonl',
                chapterCount: 3,
                totalChars: 10,
                fileSize: 1,
                createdAt: 0,
                updatedAt: 0,
              );
            },
            onOpenBook: (Book book) => opened = book,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('加入书架并下载'));
      await tester.pump();

      expect(find.textContaining('正在抓取 1/3'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(opened?.id, 'local-1');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('数据源管理页', () {
    testWidgets('空态给出「怎么写自己的源」入口', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const SourceManagerPage()));
      await tester.pumpAndSettle();

      expect(find.text('还没有安装任何数据源'), findsOneWidget);
      expect(find.text('数据源是一份 JSON 声明'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('列出已装源以及能力与状态', (WidgetTester tester) async {
      await installSource(tester);

      await tester.pumpWidget(wrap(const SourceManagerPage()));
      await tester.pumpAndSettle();

      expect(find.text('界面测试源'), findsOneWidget);
      expect(find.textContaining('搜索 · 探索 · 详情 · 目录 · 正文'), findsOneWidget);
      expect(find.textContaining('使用中'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('停用后状态变成已停用', (WidgetTester tester) async {
      await installSource(tester);
      // 开关的回调同样会写库，所以直接驱动控制器，再验证 UI 结果
      await tester.runAsync(() => sourceController.setEnabled('ui.test', false));

      await tester.pumpWidget(wrap(const SourceManagerPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('已停用'), findsWidgets);
      expect(sourceController.hasUsableSource, isFalse);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('加载失败的源会显示错误原因', (WidgetTester tester) async {
      await installSource(tester);
      await tester.runAsync(() async {
        await registry.markError('ui.test', '选择器已失效');
        await sourceController.load();
      });

      await tester.pumpWidget(wrap(const SourceManagerPage()));
      await tester.pumpAndSettle();

      expect(find.text('选择器已失效'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('配色', () {
    testWidgets('所有配色下都能构建', (WidgetTester tester) async {
      await installSource(tester);
      fetcher.route(
          '/rank?page=1', '<div class="book-item"><h3><a href="/book/101">甲书</a></h3></div>');

      for (final ReadingPalette palette in ReadingPalette.all) {
        await tester.pumpWidget(MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<SourceController>.value(value: sourceController),
            ChangeNotifierProvider<ExploreController>.value(value: exploreController),
            ChangeNotifierProvider<ReaderController>.value(value: readerController),
          ],
          child: MaterialApp(
            home: const ExplorePage(),
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blueGrey,
                brightness: palette.isDark ? Brightness.dark : Brightness.light,
              ),
              scaffoldBackgroundColor: palette.background,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('甲书'), findsOneWidget);
      }
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
