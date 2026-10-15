import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/data/app_database.dart';
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
import 'package:novel_reader/services/source/http_fetcher.dart';
import 'package:novel_reader/services/source/source_registry.dart';
import 'package:novel_reader/services/sync/sync_service.dart';
import 'package:novel_reader/services/sync/sync_transports.dart';
import 'package:novel_reader/state/bookshelf_controller.dart';
import 'package:novel_reader/state/explore_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';
import 'package:novel_reader/state/source_controller.dart';
import 'package:novel_reader/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Database db = await AppDatabase.instance.database;
  final BookDao bookDao = BookDao(db);
  final ChapterDao chapterDao = ChapterDao(db);
  final ProgressDao progressDao = ProgressDao(db);
  final BookmarkDao bookmarkDao = BookmarkDao(db);
  final NoteDao noteDao = NoteDao(db);
  final SettingsDao settingsDao = SettingsDao(db);

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

  final Directory supportDir = await getApplicationSupportDirectory();
  final String booksRoot = p.join(supportDir.path, 'books');
  final String inboxPath = p.join(supportDir.path, 'inbox');
  await Directory(inboxPath).create(recursive: true);

  final LanTransferServer lanServer = LanTransferServer(
    booksRoot: booksRoot,
    inboxPath: inboxPath,
    syncStorePath: p.join(supportDir.path, 'sync.json'),
    onFileReceived: (String filePath) {
      // 局域网收到的文件落到 inbox，由书架导入流程消费
      debugPrint('received lan file: $filePath');
    },
  );

  // 云端同步通道：地址与令牌由用户在设置页填写，程序不内置默认值
  final SyncTransport syncTransport = CloudSyncTransport(
    baseUrl: 'https://sync.example.invalid',
    apiToken: '',
  );
  final ProgressSyncService syncService = ProgressSyncService(
    progressDao: progressDao,
    bookmarkDao: bookmarkDao,
    noteDao: noteDao,
    transport: syncTransport,
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

  // ---- 在线数据源 ----
  // 传输层与源层分开：传输层（HttpFetcher）可以被换成内存桩，
  // 于是源注册表、规则引擎、在线仓库全部能脱离网络测试。
  final SourceRegistry sourceRegistry = SourceRegistry(
    dao: SourceDao(db),
    fetcher: IoHttpFetcher(),
  );
  final OnlineBookRepository onlineBookRepository = OnlineBookRepository(
    registry: sourceRegistry,
    cacheDao: ChapterCacheDao(db),
    bookRepository: bookRepository,
  );
  final SourceController sourceController = SourceController(registry: sourceRegistry);
  await sourceController.load();

  final ExploreController exploreController = ExploreController(
    registry: sourceRegistry,
    repository: onlineBookRepository,
  );

  runApp(NovelReaderApp(
    settingsController: settingsController,
    bookshelfController: bookshelfController,
    readerController: readerController,
    lanServer: lanServer,
    syncService: syncService,
    sourceController: sourceController,
    exploreController: exploreController,
  ));
}
