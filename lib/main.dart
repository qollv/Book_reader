import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/data/app_database.dart';
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
import 'package:novel_reader/services/import/lan_transfer_server.dart';
import 'package:novel_reader/services/import/local_file_importer.dart';
import 'package:novel_reader/services/import/url_importer.dart';
import 'package:novel_reader/services/sync/sync_service.dart';
import 'package:novel_reader/state/bookshelf_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';
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

  final AppStateDao appStateDao = AppStateDao(db);

  final LanTransferServer lanServer = LanTransferServer(
    booksRoot: booksRoot,
    inboxPath: inboxPath,
    syncStorePath: p.join(supportDir.path, 'sync.json'),
    onFileReceived: (String filePath) {
      // 局域网收到的文件落到 inbox，由书架导入流程消费
      debugPrint('received lan file: $filePath');
    },
  );

  // 同步传输通道在用户点击同步时按 app_state 里的配置现场构造，
  // 程序不内置任何默认端点。
  final ProgressSyncService syncService = ProgressSyncService(
    progressDao: progressDao,
    bookmarkDao: bookmarkDao,
    noteDao: noteDao,
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

  runApp(NovelReaderApp(
    settingsController: settingsController,
    bookshelfController: bookshelfController,
    readerController: readerController,
    lanServer: lanServer,
    syncService: syncService,
    appStateDao: appStateDao,
  ));
}
