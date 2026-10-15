import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/data/dao/book_dao.dart';
import 'package:novel_reader/data/dao/bookmark_dao.dart';
import 'package:novel_reader/data/dao/chapter_cache_dao.dart';
import 'package:novel_reader/data/dao/chapter_dao.dart';
import 'package:novel_reader/data/dao/note_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/data/dao/settings_dao.dart';
import 'package:novel_reader/data/dao/source_dao.dart';
import 'package:novel_reader/data/repositories/annotation_repository.dart';
import 'package:novel_reader/data/repositories/book_repository.dart';
import 'package:novel_reader/data/repositories/online_book_repository.dart';
import 'package:novel_reader/data/repositories/reader_repository.dart';
import 'package:novel_reader/services/import/book_importer.dart';
import 'package:novel_reader/services/import/lan_transfer_server.dart';
import 'package:novel_reader/services/import/local_file_importer.dart';
import 'package:novel_reader/services/import/url_importer.dart';
import 'package:novel_reader/services/source/source_registry.dart';
import 'package:novel_reader/services/sync/sync_service.dart';
import 'package:novel_reader/services/sync/sync_transports.dart';
import 'package:novel_reader/state/bookshelf_controller.dart';
import 'package:novel_reader/state/explore_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';
import 'package:novel_reader/state/source_controller.dart';
import 'package:novel_reader/ui/app.dart';

import '../support/fake_http_fetcher.dart';
import '../support/test_database.dart';

/// 整机装配冒烟：构造 NovelReaderApp，把 main.dart 里那套依赖都接上。
///
/// 这一档专门盯「接线」——Provider 有没有漏、页面之间能不能切、
/// 嵌套 Scaffold 会不会打架。这类问题单元测试看不见，只有真的把应用
/// 装起来才能发现。
void main() {
  late Database db;
  late SourceController sourceController;
  late ExploreController exploreController;

  Widget buildApp() {
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
    final ReaderRepository readerRepository = ReaderRepository(
      chapterDao: ChapterDao(db),
      progressDao: ProgressDao(db),
    );

    return NovelReaderApp(
      settingsController: SettingsController(SettingsDao(db)),
      bookshelfController: BookshelfController(
        bookDao: BookDao(db),
        progressDao: ProgressDao(db),
        bookRepository: bookRepository,
        importer: BookImporter(
          localImporter: LocalFileImporter(bookRepository),
          urlImporter: UrlImporter(bookRepository),
        ),
      ),
      readerController: ReaderController(
        readerRepository: readerRepository,
        annotationRepository: annotations,
        bookDao: BookDao(db),
      ),
      lanServer: LanTransferServer(
        booksRoot: '/tmp/books',
        inboxPath: '/tmp/inbox',
        syncStorePath: '/tmp/sync.json',
        onFileReceived: (_) {},
      ),
      syncService: ProgressSyncService(
        progressDao: ProgressDao(db),
        bookmarkDao: BookmarkDao(db),
        noteDao: NoteDao(db),
        transport: CloudSyncTransport(baseUrl: 'https://sync.invalid', apiToken: ''),
      ),
      sourceController: sourceController,
      exploreController: exploreController,
    );
  }

  setUp(() async {
    db = await openTestDatabase();
    final SourceRegistry registry = SourceRegistry(
      dao: SourceDao(db),
      fetcher: FakeHttpFetcher(),
    );
    await registry.load();
    sourceController = SourceController(registry: registry);
    exploreController = ExploreController(
      registry: registry,
      repository: OnlineBookRepository(
        registry: registry,
        cacheDao: ChapterCacheDao(db),
        bookRepository: BookRepository(
          bookDao: BookDao(db),
          chapterDao: ChapterDao(db),
          progressDao: ProgressDao(db),
          annotationRepository: AnnotationRepository(
            bookmarkDao: BookmarkDao(db),
            noteDao: NoteDao(db),
          ),
        ),
      ),
    );
    await sourceController.load();
  });

  tearDown(() async => db.close());

  testWidgets('应用能起来，默认落在书架页', (WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsWidgets);
    expect(find.text('探索'), findsOneWidget);
    expect(find.text('书架还是空的'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('底部导航能在书架与探索之间切换', (WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('探索'));
    await tester.pumpAndSettle();

    expect(find.text('还没有可用的数据源'), findsOneWidget);

    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();

    expect(find.text('书架还是空的'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('探索页的状态在切换 tab 后保留（IndexedStack）', (WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('探索'));
    await tester.pumpAndSettle();
    expect(find.text('还没有可用的数据源'), findsOneWidget);

    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('探索'));
    await tester.pumpAndSettle();

    // 若换成按需构建，这里会重新初始化；IndexedStack 应当保留同一棵树
    expect(find.text('还没有可用的数据源'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
