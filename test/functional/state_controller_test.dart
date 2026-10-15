import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/data/dao/book_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/data/dao/settings_dao.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/services/import/book_importer.dart';
import 'package:novel_reader/services/import/local_file_importer.dart';
import 'package:novel_reader/services/import/url_importer.dart';
import 'package:novel_reader/state/bookshelf_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';

import 'test_support.dart';

/// 书架/设置控制器功能测试（FT-STATE 系列）。
void main() {
  group('FT-STATE 控制器', () {
    late TestHarness harness;

    setUp(() async {
      harness = await createHarness();
    });

    tearDown(() async {
      await harness.dispose();
    });

    /// 构造一个 importFromUrl 必然抛错的控制器（DAO 用真实内存库）。
    BookshelfController throwingController(Object error) => BookshelfController(
          bookDao: BookDao(harness.database),
          progressDao: ProgressDao(harness.database),
          bookRepository: harness.bookRepository,
          importer: _ThrowingImporter(error, harness),
        );

    test('FT-STATE-01 空书架加载得到空列表', () async {
      expect(harness.bookshelfController.items, isEmpty);
      expect(harness.bookshelfController.isImporting, isFalse);
    });

    test('FT-STATE-02 导入失败错误文案对用户友好（ImportException 中文直出）', () async {
      final BookshelfController controller = throwingController(
        const ImportException('只支持 http/https 链接'),
      );
      final Book? result = await controller.importFromUrl('ftp://x/book.txt');
      expect(result, isNull);
      expect(controller.importError, '只支持 http/https 链接');
      expect(controller.isImporting, isFalse, reason: '异常后导入中状态必须复位');
      controller.clearError();
      expect(controller.importError, isNull);
      controller.dispose();
    });

    test('FT-STATE-03 非 ImportException 异常也兜底为字符串（不裸抛）', () async {
      final BookshelfController controller =
          throwingController(Exception('boom'));
      final Book? result = await controller.importFromUrl('http://x/book.txt');
      expect(result, isNull);
      expect(controller.importError, isNotEmpty);
      controller.dispose();
    });

    test('FT-STATE-04 导入成功后书架列表刷新（进度 0%）', () async {
      await harness.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      await harness.bookshelfController.load();
      expect(harness.bookshelfController.items.length, 1);
      expect(harness.bookshelfController.items.first.book.title, '雨夜听刀');
      expect(harness.bookshelfController.items.first.percent, 0);
    });

    test('FT-STATE-05 删书后书架移除该书', () async {
      await harness.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      await harness.bookshelfController.load();
      final String bookId = harness.bookshelfController.items.first.book.id;
      await harness.bookshelfController.deleteBook(bookId);
      expect(harness.bookshelfController.items, isEmpty);
    });

    test('FT-STATE-06 设置持久化往返：update 后新控制器 load 得到同值', () async {
      await harness.settingsController.setFontScale(1.4);
      await harness.settingsController.setPalette(3);
      await harness.settingsController.setThemeMode(ThemeMode.dark);

      // 模拟重启：同一 DAO 上新控制器
      final SettingsController fresh =
          SettingsController(SettingsDao(harness.database));
      await fresh.load();
      expect(fresh.settings.fontScale, 1.4);
      expect(fresh.settings.paletteIndex, 3);
      expect(fresh.settings.themeMode, ThemeMode.dark);
      fresh.dispose();
    });

    test('FT-STATE-07 设置脏数据不崩溃：非法 JSON 回落默认值', () async {
      final SettingsDao dao = SettingsDao(harness.database);
      final SettingsController fresh = SettingsController(dao);

      await dao.save('这不是JSON');
      await fresh.load();
      expect(fresh.settings.fontScale, ReaderSettings.defaults().fontScale);
      expect(fresh.settings.paletteIndex, ReaderSettings.defaults().paletteIndex);

      await dao.save('{"font_scale": "abc", "palette_index": 999, "line_height": -5}');
      await fresh.load();
      expect(fresh.settings.fontScale, ReaderSettings.defaults().fontScale);
      expect(fresh.settings.paletteIndex, 4,
          reason: 'palette_index 999 应被 clamp 到最大合法档');
      expect(fresh.settings.lineHeight, ReaderSettings.lineHeightMin);
      fresh.dispose();
    });
  });
}

/// 导入必然失败的 BookImporter（用于控制器错误路径测试）。
class _ThrowingImporter extends BookImporter {
  _ThrowingImporter(this._error, TestHarness harness)
      : super(
          localImporter: LocalFileImporter(harness.bookRepository),
          urlImporter: UrlImporter(harness.bookRepository),
        );

  final Object _error;

  @override
  Future<Book> fromUrl(String url,
      {void Function(int received, int total)? onProgress}) async {
    throw _error;
  }

  @override
  Future<Book?> pickLocal() async {
    throw _error;
  }
}
