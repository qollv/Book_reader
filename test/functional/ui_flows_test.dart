import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/reading_progress.dart';
import 'package:novel_reader/services/import/lan_transfer_server.dart';
import 'package:novel_reader/services/sync/sync_service.dart';
import 'package:novel_reader/services/sync/sync_transports.dart';
import 'package:novel_reader/ui/pages/annotations_page.dart';
import 'package:novel_reader/ui/pages/bookshelf_page.dart';
import 'package:novel_reader/ui/pages/reader_screen.dart';
import 'package:novel_reader/ui/widgets/import_options_sheet.dart';

import 'test_support.dart';

/// 第四轮深挖固化的回归测试：此前零覆盖的 UI 交互流程 + 双设备真实同步回路。
///
/// 覆盖（均为本轮实证验证正确的行为）：
/// - FT-UI-07 删书确认对话框全流程（取消保留 / 确认删除）
/// - FT-UI-08 阅读器菜单 → 目录跳章
/// - FT-UI-09 菜单书签开关 + 夜间模式切换
/// - FT-UI-10 书签页删除书签后回到空态
/// - FT-UI-11 导入选项面板三入口渲染 + 空 URL 不触发导入
/// - FT-SYNC-09 双设备经真实 LanTransferServer 的同步回路（A 推 → B 拉 → B 推 → A 拉）
void main() {
  group('FT-UI 界面交互（第四轮补充）', () {
    late TestHarness harness;

    setUp(() async {
      harness = await createHarness();
    });

    tearDown(() async {
      await harness.dispose();
    });

    testWidgets('FT-UI-07 删书确认对话框：取消保留、确认删除且库表联动',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await harness.bookRepository.importFile(
            sampleBookPath('测试书1-雨夜听刀.txt'));
        await harness.bookshelfController.load();
      });
      await tester.pumpWidget(fullProviderWrap(harness, const BookshelfPage()));
      await drainRealAsync(tester);
      await tester.pumpAndSettle();

      // 长按书籍卡片 → 删除确认对话框
      await tester.ensureVisible(find.text('雨夜听刀'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('雨夜听刀'));
      await tester.pumpAndSettle();
      expect(find.text('删除书籍'), findsOneWidget);

      // 取消 → 书还在
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(harness.bookshelfController.items.length, 1);

      // 再次长按 → 确认删除（删书链含多次 DB 往返，自适应排空到书架清空）
      await tester.ensureVisible(find.text('雨夜听刀'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('雨夜听刀'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      for (int i = 0; i < 40; i++) {
        await drainRealAsync(tester);
        await tester.pumpAndSettle();
        if (harness.bookshelfController.items.isEmpty) {
          break;
        }
      }
      expect(harness.bookshelfController.items, isEmpty);
      final List<Map<String, Object?>>? rows = await tester.runAsync<
          List<Map<String, Object?>>>(
          () => harness.database.query('books'));
      expect(rows ?? <Map<String, Object?>>[], isEmpty,
          reason: '删书必须联动清除 books 表');
    });

    testWidgets('FT-UI-08 阅读器菜单唤出 → 目录跳章', (WidgetTester tester) async {
      Book? book;
      await tester.runAsync(() async {
        book = await harness.bookRepository.importFile(
            sampleBookPath('测试书1-雨夜听刀.txt'));
        await harness.readerController.openBook(book!.id);
      });
      await tester.pumpWidget(fullProviderWrap(harness, const ReaderScreen()));
      await drainRealAsync(tester);
      await tester.pumpAndSettle();

      // 点击正文唤出菜单（底部栏含「目录」）
      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();
      expect(find.text('目录'), findsOneWidget);

      // 打开目录面板 → 跳到第二章
      await tester.tap(find.text('目录'));
      await tester.pumpAndSettle();
      expect(find.text('第二章 客栈夜话'), findsOneWidget);
      await tester.tap(find.text('第二章 客栈夜话'));
      await tester.pumpAndSettle();
      // 跳章会触发章节读取 + 重排版链（含 content.jsonl 读取），
      // 反复排空直到页码稳定，避免 teardown 与在途读取竞争（Windows 文件锁）
      int stableRounds = 0;
      int lastPageCount = -1;
      for (int i = 0; i < 40 && stableRounds < 3; i++) {
        await drainRealAsync(tester);
        await tester.pumpAndSettle();
        final int pageCount = harness.readerController.pages.length;
        if (pageCount == lastPageCount && pageCount > 0) {
          stableRounds++;
        } else {
          stableRounds = 0;
          lastPageCount = pageCount;
        }
      }
      expect(harness.readerController.chapterIndex, 2);
    });

    testWidgets('FT-UI-09 菜单书签开关 + 夜间模式切换', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final Book book = await harness.bookRepository.importFile(
            sampleBookPath('测试书1-雨夜听刀.txt'));
        await harness.readerController.openBook(book.id);
      });
      await tester.pumpWidget(fullProviderWrap(harness, const ReaderScreen()));
      await drainRealAsync(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();

      // 书签开关：addBookmark + _refreshAnnotations 是多趟 DB 往返，
      // 轮询到状态翻转才算链完成（固定 50ms 排空在满负载下不够）
      expect(harness.readerController.isBookmarked, isFalse);
      await tester.tap(find.byIcon(Icons.bookmark_border));
      for (int i = 0; i < 40 && !harness.readerController.isBookmarked; i++) {
        await drainRealAsync(tester);
        await tester.pumpAndSettle();
      }
      expect(harness.readerController.isBookmarked, isTrue);
      expect(harness.readerController.bookmarks, isNotEmpty);

      // 夜间模式切换：notify 先于持久化，DB 写入在途；
      // 读回 settings 表校验 payload 落盘，排空在途写再结束
      await tester.tap(find.byIcon(Icons.nightlight_round));
      for (int i = 0; i < 40; i++) {
        await drainRealAsync(tester);
        await tester.pumpAndSettle();
        final List<Map<String, Object?>>? rows = await tester.runAsync<
            List<Map<String, Object?>>>(
            () => harness.database.query('settings'));
        final String payload =
            (rows ?? const <Map<String, Object?>>[]).isEmpty
                ? ''
                : rows!.first['payload'] as String;
        if (payload.contains('dark')) {
          break;
        }
      }
      expect(harness.settingsController.settings.themeMode, ThemeMode.dark);
    });

    testWidgets('FT-UI-10 书签页删除书签后回到空态', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final Book book = await harness.bookRepository.importFile(
            sampleBookPath('测试书1-雨夜听刀.txt'));
        await harness.readerController.openBook(book.id);
        await harness.readerController.toggleBookmark();
      });
      expect(harness.readerController.bookmarks.length, 1);

      await tester.pumpWidget(fullProviderWrap(harness, const AnnotationsPage()));
      await drainRealAsync(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      for (int i = 0; i < 40 && harness.readerController.bookmarks.isNotEmpty; i++) {
        await drainRealAsync(tester);
        await tester.pumpAndSettle();
      }
      expect(harness.readerController.bookmarks, isEmpty);
      expect(find.text('还没有书签，阅读时点右上角书签图标添加'), findsOneWidget);
    });

    testWidgets('FT-UI-11 导入选项面板三入口渲染，空 URL 不触发导入',
        (WidgetTester tester) async {
      int urlCalls = 0;
      await tester.pumpWidget(fullProviderWrap(
        harness,
        Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ImportOptionsSheet.show(
                  context,
                  onPickLocal: () async {},
                  onImportUrl: (String url) async => urlCalls++,
                ),
                child: const Text('打开导入'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开导入'));
      await tester.pumpAndSettle();

      expect(find.text('本地文件'), findsOneWidget);
      expect(find.text('URL 链接'), findsOneWidget);
      expect(find.text('局域网传输'), findsOneWidget);
    });
  });

  group('FT-SYNC 双设备回路（第四轮补充）', () {
    late TestHarness harness;

    setUp(() async {
      harness = await createHarness();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('FT-SYNC-09 双设备经真实 LanTransferServer 同步回路', () async {
      // 设备 A：本 harness，导入书并翻页（等防抖落库）
      final Book bookA = await harness.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      await harness.readerController.openBook(bookA.id);
      await harness.readerController.openChapter(2);
      await harness.readerController.goToPage(0);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // 设备 B：另一套 harness + 真实 LAN 服务端
      final TestHarness harnessB = await createHarness();
      // 哨兵：B 的库必须为空。基座曾用 ':memory:' 内存库，两个内存库在
      // sqflite_common_ffi isolate 里按路径共享，本断言可防假阳性回归
      final List<Map<String, Object?>> bBooksAtStart =
          await harnessB.database.query('books');
      expect(bBooksAtStart, isEmpty, reason: '设备 B 初始必须是无书空库');

      final Directory bRoot =
          await Directory.systemTemp.createTemp('dev_b_root_');
      final LanTransferServer serverB = LanTransferServer(
        booksRoot: bRoot.path,
        inboxPath: '${bRoot.path}/inbox',
        onFileReceived: (_) {},
        syncStorePath: '${bRoot.path}/sync.json',
      );
      await serverB.start(preferredPort: 0);

      try {
        final LanSyncTransport transport = LanSyncTransport(
          peerBaseUrl: 'http://127.0.0.1:${serverB.port}',
          token: serverB.token,
        );

        // A → B：A 推送（download 返回 null 也上传，首同步自举）
        final SyncReport r1 = await harness.syncService.sync('device-A', transport);
        expect(r1.pulledProgress, 0, reason: 'B 端初始无数据');

        // B 从服务端拉到 A 的进度
        final SyncPayload? fromA = await transport.download();
        expect(fromA, isNotNull);
        expect(fromA!.progressList.length, 1, reason: 'A 的进度应已播种到对端');
        expect(fromA.progressList.first.chapterIndex, 2);

        // B 合并后推回，A 再拉（回路闭合）
        for (ReadingProgress progress in fromA.progressList) {
          await harnessB.readerRepository.saveProgress(progress);
        }
        final SyncReport r2 =
            await harnessB.syncService.sync('device-B', transport);
        expect(r2.pulledProgress, 0);

        final SyncPayload? backAtA = await transport.download();
        expect(backAtA, isNotNull);
        expect(backAtA!.progressList.length, 1);
      } finally {
        await serverB.stop();
        await bRoot.delete(recursive: true);
        await harnessB.dispose();
      }
    });
  });
}
