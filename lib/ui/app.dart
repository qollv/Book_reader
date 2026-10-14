import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/data/dao/app_state_dao.dart';
import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/services/import/lan_transfer_server.dart';
import 'package:novel_reader/services/sync/sync_service.dart';
import 'package:novel_reader/state/bookshelf_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';
import 'package:novel_reader/ui/pages/bookshelf_page.dart';
import 'package:novel_reader/models/reading_palette.dart';
import 'package:novel_reader/ui/theme/theme_mode_resolver.dart';

class NovelReaderApp extends StatelessWidget {
  const NovelReaderApp({
    super.key,
    required this.settingsController,
    required this.bookshelfController,
    required this.readerController,
    required this.lanServer,
    required this.syncService,
    required this.appStateDao,
  });

  final SettingsController settingsController;
  final BookshelfController bookshelfController;
  final ReaderController readerController;
  final LanTransferServer lanServer;
  final ProgressSyncService syncService;
  final AppStateDao appStateDao;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<SettingsController>.value(value: settingsController),
        ChangeNotifierProvider<BookshelfController>.value(value: bookshelfController),
        ChangeNotifierProvider<ReaderController>.value(value: readerController),
      ],
      child: MultiProvider(
        providers: <Provider<Object>>[
          Provider<LanTransferServer>.value(value: lanServer),
          Provider<ProgressSyncService>.value(value: syncService),
          Provider<AppStateDao>.value(value: appStateDao),
        ],
        child: Consumer<SettingsController>(
          builder: (BuildContext context, SettingsController settingsController, Widget? child) {
            final ReaderSettings settings = settingsController.settings;
            final ReadingPalette palette = ReadingPalette.all[settings.paletteIndex];
            return MaterialApp(
              title: '小说阅读器',
              debugShowCheckedModeBanner: false,
              themeMode: resolveThemeMode(settings),
              theme: _buildTheme(palette, false),
              darkTheme: _buildTheme(palette, true),
              home: const BookshelfPage(),
            );
          },
        ),
      ),
    );
  }

  ThemeData _buildTheme(ReadingPalette palette, bool isDark) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: palette.isDark ? Colors.blueGrey : Colors.brown,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.text,
        elevation: 0,
      ),
      textTheme: TextTheme(bodyMedium: TextStyle(color: palette.text)),
    );
  }
}
