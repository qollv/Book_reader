import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/state/bookshelf_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';
import 'package:novel_reader/ui/pages/annotations_page.dart';
import 'package:novel_reader/ui/pages/bookshelf_page.dart';
import 'package:novel_reader/ui/pages/reader_screen.dart';
import 'package:novel_reader/ui/theme/theme_mode_resolver.dart';
import 'package:novel_reader/ui/widgets/reader_settings_sheet.dart';

import 'test_support.dart';

/// UI 冒烟功能测试（FT-UI 系列）。
///
/// 异步模型（关键，来自 flutter_test binding 源码实测）：
/// testWidgets 的 body 运行在 FakeAsync 作用域内，真实异步 I/O
/// （sqflite ffi / 文件 / HTTP）在 body 内直接 await 永远不会完成，
/// 必须经 tester.runAsync 在真实异步区执行或等待。
/// 页面自身 post-frame 回调（书架 load / 阅读器 repaginate / 设置持久化）
/// 同样要在测试结束前排空，否则 tearDown 关闭数据库后回调才落地，
/// 会触发「使用已 dispose 的控制器」或「写已关闭的数据库」的 post-test 异常。
Future<void> drainRealAsync(WidgetTester tester) => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

void main() {
  group('FT-UI 界面', () {
    late TestHarness harness;

    setUp(() async {
      // setUp 在 FakeAsync 之外执行，真实 I/O 可正常完成
      harness = await createHarness();
    });

    tearDown(() async {
      await harness.dispose();
    });

    Widget wrap(Widget child) => MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<BookshelfController>.value(
                value: harness.bookshelfController),
            ChangeNotifierProvider<ReaderController>.value(
                value: harness.readerController),
            ChangeNotifierProvider<SettingsController>.value(
                value: harness.settingsController),
          ],
          child: MaterialApp(
            home: child,
            themeMode: resolveThemeMode(harness.settingsController.settings),
          ),
        );

    testWidgets('FT-UI-01 空书架：空态文案与导入入口', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const BookshelfPage()));
      // 页面 initState 的 post-frame load() 是真实 DB I/O，需排空
      await drainRealAsync(tester);
      await tester.pumpAndSettle();

      expect(find.text('书架还是空的'), findsOneWidget);
      expect(find.text('点右下角 + 导入 txt / md / docx'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('书架'), findsOneWidget);
    });

    testWidgets('FT-UI-02 有书书架：封面字/书名/已读百分比', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await harness.bookRepository.importFile(
            sampleBookPath('测试书1-雨夜听刀.txt'));
        await harness.bookshelfController.load();
      });

      await tester.pumpWidget(wrap(const BookshelfPage()));
      await drainRealAsync(tester);
      await tester.pumpAndSettle();

      expect(find.text('雨'), findsOneWidget, reason: '封面取书名首字');
      expect(find.text('雨夜听刀'), findsOneWidget);
      expect(find.textContaining('已读 0%'), findsOneWidget);
      expect(find.textContaining('未知作者'), findsOneWidget);
    });

    testWidgets('FT-UI-03 阅读器错误页：失败文案 + 返回书架出口',
        (WidgetTester tester) async {
      await tester.runAsync(
          () => harness.readerController.openBook('missing-id'));
      await tester.pumpWidget(wrap(const ReaderScreen()));
      await drainRealAsync(tester);
      await tester.pumpAndSettle();

      expect(find.text('书籍不存在或已被删除'), findsOneWidget);
      expect(find.text('返回书架'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('FT-UI-04 阅读器正常渲染：正文首块上屏', (WidgetTester tester) async {
      Book? book;
      await tester.runAsync(() async {
        book = await harness.bookRepository.importFile(
            sampleBookPath('测试书1-雨夜听刀.txt'));
        harness.readerController.provideConfig(const PaginationConfig(
          fontSize: 18,
          lineHeight: 1.8,
          pageWidth: 400,
          pageHeight: 600,
          horizontalMargin: 24,
          verticalMargin: 20,
        ));
        await harness.readerController.openBook(book!.id);
      });

      await tester.pumpWidget(wrap(const ReaderScreen()));
      // build 的 provideConfig + post-frame repaginate 是真实 DB I/O，需排空
      await drainRealAsync(tester);
      await tester.pumpAndSettle();

      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('作者：测试用户'), findsOneWidget,
          reason: '首章「正文」第二行应渲染上屏');
    });

    testWidgets('FT-UI-05 设置面板：全部分区渲染且可切换显示模式',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ReaderSettingsSheet.show(context),
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();

      for (String section in <String>[
        '阅读设置', '显示模式', '配色', '字体', '字号', '行距', '页边距', '翻页方式',
      ]) {
        expect(find.text(section), findsOneWidget, reason: '设置分区 [$section] 应渲染');
      }

      // 切换显示模式 → 控制器内存状态即时变更。
      // DEF-09 修复后 SettingsController.update 先 notifyListeners 再持久化，
      // UI 立即重建；drainRealAsync 仍用于排空页面自身的 post-frame 回调。
      await tester.tap(find.text('日间'));
      await tester.pumpAndSettle();
      await drainRealAsync(tester);
      await tester.pumpAndSettle();
      expect(harness.settingsController.settings.themeMode, ThemeMode.light);

      // 切换配色 → 夜间配色索引 3
      await tester.tap(find.widgetWithText(ChoiceChip, '夜间'));
      await tester.pumpAndSettle();
      await drainRealAsync(tester);
      await tester.pumpAndSettle();
      expect(harness.settingsController.settings.paletteIndex, 3);

      // 显式日间 + 夜间配色 → 仍为日间：显式选择优先（当前实现行为，见报告 P4）
      expect(resolveThemeMode(harness.settingsController.settings),
          ThemeMode.light,
          reason: '显式显示模式优先于配色强制');

      // 跟随系统 + 夜间配色 → 强制深色（theme_mode_resolver 规则本体）
      await tester.tap(find.text('跟随系统'));
      await tester.pumpAndSettle();
      await drainRealAsync(tester);
      await tester.pumpAndSettle();
      expect(harness.settingsController.settings.themeMode, ThemeMode.system);
      expect(resolveThemeMode(harness.settingsController.settings),
          ThemeMode.dark,
          reason: '系统模式下夜间配色强制深色');
    });

    testWidgets('FT-UI-06 书签与笔记页空态', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const AnnotationsPage()));
      await tester.pumpAndSettle();

      expect(find.text('还没有书签，阅读时点右上角书签图标添加'), findsOneWidget);
      // TabBarView 懒构建：切到笔记 Tab 后再断言
      await tester.tap(find.text('笔记'));
      await tester.pumpAndSettle();
      expect(find.text('还没有笔记，阅读时长按正文行即可记笔记'), findsOneWidget);
    });
  });
}
