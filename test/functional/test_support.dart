import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'package:novel_reader/data/dao/app_state_dao.dart';
import 'package:novel_reader/data/dao/book_dao.dart';
import 'package:novel_reader/data/dao/bookmark_dao.dart';
import 'package:novel_reader/data/dao/chapter_dao.dart';
import 'package:novel_reader/data/dao/note_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/data/dao/settings_dao.dart';
import 'package:novel_reader/data/repositories/annotation_repository.dart';
import 'package:novel_reader/data/repositories/book_repository.dart';
import 'package:novel_reader/data/repositories/reader_repository.dart';
import 'package:novel_reader/services/import/book_importer.dart';
import 'package:novel_reader/services/import/local_file_importer.dart';
import 'package:novel_reader/services/import/url_importer.dart';
import 'package:novel_reader/services/sync/sync_service.dart';
import 'package:novel_reader/state/bookshelf_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';

/// 功能测试共享基座。
///
/// 说明：
/// - 桌面环境没有 sqflite 的 native 插件，用 sqflite_common_ffi 内存库跑真实 DAO；
/// - 表结构镜像自 AppDatabase._createTables（私有），schema 演进时需同步本文件；
/// - path_provider 用假实现指向临时目录，getApplicationSupportDirectory 才可用。

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.supportDir);

  final String supportDir;

  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

/// 一次功能测试的完整装配：内存库 + 真实 DAO/仓库/控制器。
class TestHarness {
  TestHarness({
    required this.database,
    required this.supportDir,
    required this.bookRepository,
    required this.readerRepository,
    required this.annotationRepository,
    required this.bookImporter,
    required this.bookshelfController,
    required this.readerController,
    required this.settingsController,
    required this.syncService,
    required this.appStateDao,
  });

  final sqflite.Database database;
  final Directory supportDir;
  final BookRepository bookRepository;
  final ReaderRepository readerRepository;
  final AnnotationRepository annotationRepository;
  final BookImporter bookImporter;
  final BookshelfController bookshelfController;
  final ReaderController readerController;
  final SettingsController settingsController;
  final ProgressSyncService syncService;
  final AppStateDao appStateDao;

  Future<void> dispose({bool disposeControllers = true}) async {
    if (disposeControllers) {
      readerController.dispose();
      bookshelfController.dispose();
      settingsController.dispose();
    }
    await database.close();
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
  }
}

/// 与 AppDatabase._createTables 保持一致的建表脚本（schema 演进需同步）。
Future<void> createSchemaForTest(sqflite.Database db) async {
  await db.execute('''
    CREATE TABLE books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
      format TEXT NOT NULL,
      content_path TEXT NOT NULL,
      chapter_count INTEGER NOT NULL,
      total_chars INTEGER NOT NULL,
      file_size INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE chapters (
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      title TEXT NOT NULL,
      paragraph_start INTEGER NOT NULL,
      paragraph_end INTEGER NOT NULL,
      PRIMARY KEY (book_id, chapter_index)
    )
  ''');
  await db.execute('''
    CREATE TABLE progress (
      book_id TEXT PRIMARY KEY,
      chapter_index INTEGER NOT NULL,
      paragraph_index INTEGER NOT NULL,
      line_index INTEGER NOT NULL,
      percent REAL NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE bookmarks (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      paragraph_index INTEGER NOT NULL,
      line_index INTEGER NOT NULL,
      chapter_title TEXT NOT NULL,
      excerpt TEXT NOT NULL,
      comment TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE notes (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      paragraph_index INTEGER NOT NULL,
      line_index INTEGER NOT NULL,
      chapter_title TEXT NOT NULL,
      selected_text TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY CHECK (id = 0),
      payload TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE app_state (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
}

/// 装配一套完整 harness（内存库 + 假 path_provider）。
Future<TestHarness> createHarness() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 的 binding 会全局安装 MockHttpClient（所有请求一律 400、不发网络），
  // 功能测试需要真实本地 HTTP（URL 导入/同步通道），这里恢复默认 HttpClient。
  HttpOverrides.global = null;
  sqfliteFfiInit();
  sqflite.databaseFactory = databaseFactoryFfi;

  final Directory supportDir =
      await Directory.systemTemp.createTemp('novel_harness_');
  PathProviderPlatform.instance = _FakePathProviderPlatform(supportDir.path);

  final sqflite.Database db = await databaseFactoryFfi.openDatabase(
    ':memory:',
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (sqflite.Database db, int version) => createSchemaForTest(db),
    ),
  );

  final BookDao bookDao = BookDao(db);
  final ChapterDao chapterDao = ChapterDao(db);
  final ProgressDao progressDao = ProgressDao(db);
  final BookmarkDao bookmarkDao = BookmarkDao(db);
  final NoteDao noteDao = NoteDao(db);
  final SettingsDao settingsDao = SettingsDao(db);
  final AppStateDao appStateDao = AppStateDao(db);

  final AnnotationRepository annotationRepository =
      AnnotationRepository(bookmarkDao: bookmarkDao, noteDao: noteDao);
  final BookRepository bookRepository = BookRepository(
    bookDao: bookDao,
    chapterDao: chapterDao,
    progressDao: progressDao,
    annotationRepository: annotationRepository,
  );
  final ReaderRepository readerRepository =
      ReaderRepository(chapterDao: chapterDao, progressDao: progressDao);
  final BookImporter bookImporter = BookImporter(
    localImporter: LocalFileImporter(bookRepository),
    urlImporter: UrlImporter(bookRepository),
  );

  final SettingsController settingsController = SettingsController(settingsDao);
  await settingsController.load();
  final BookshelfController bookshelfController = BookshelfController(
    bookDao: bookDao,
    progressDao: progressDao,
    bookRepository: bookRepository,
    importer: bookImporter,
  );
  await bookshelfController.load();
  final ReaderController readerController = ReaderController(
    readerRepository: readerRepository,
    annotationRepository: annotationRepository,
    bookDao: bookDao,
  );

  return TestHarness(
    database: db,
    supportDir: supportDir,
    bookRepository: bookRepository,
    readerRepository: readerRepository,
    annotationRepository: annotationRepository,
    bookImporter: bookImporter,
    bookshelfController: bookshelfController,
    readerController: readerController,
    settingsController: settingsController,
    syncService: ProgressSyncService(
      progressDao: progressDao,
      bookmarkDao: bookmarkDao,
      noteDao: noteDao,
    ),
    appStateDao: appStateDao,
  );
}

/// 测试样例书目录（仓库根 test_books）。
/// flutter test 的当前目录是包目录（novel_reader），上溯一级到仓库根。
String sampleBookPath(String name) => p.normalize(
      p.join(Directory.current.path, '..', 'test_books', name),
    );
