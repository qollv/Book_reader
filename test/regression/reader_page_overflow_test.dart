import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/line_box.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/ui/pages/reader_screen.dart';
import 'package:novel_reader/ui/theme/reading_palettes.dart';

/// 分页与渲染一致性的回归测试（量真实像素）。
///
/// 原来这里有个只有渲染才看得见的 bug：分页器只按**文字高度**排版，
/// 渲染器却给不同段落类型额外加内外边距 —— 代码块每行上下各 0.2 字号
/// 的外边距 + 0.5 字号的内边距，小屏上实测溢出 120px（渲染 400.4px /
/// 可用 280px）。此外代码块渲染换成了等宽字体，而分页仍按比例字体测量，
/// 字体度量不同也让「量得下」失准。
///
/// 单元测试看不见这个问题，因为它两个实现各测各的。所以这里把
/// 分页结果**真的渲染出来**，量内容实际高度，断言它不超过可用高度。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PaginationConfig configFor({
    double pageHeight = 400,
    double fontSize = 18,
  }) {
    return PaginationConfig(
      fontSize: fontSize,
      lineHeight: 1.8,
      pageWidth: 360,
      pageHeight: pageHeight,
      horizontalMargin: 24,
      verticalMargin: 20,
    );
  }

  const List<ParagraphBlock> mixedContent = <ParagraphBlock>[
    ParagraphBlock(text: '第一章 起风了', kind: ParagraphKind.heading),
    ParagraphBlock(
      text: '这是正文第一段，用来占据若干行高度，验证普通段落的排版是否准确。'
          '再补一些字让它至少折成两行，这样边界情况才测得到。',
      kind: ParagraphKind.paragraph,
    ),
    ParagraphBlock(
      text: '引用一行，看看带左侧边线的引用块是否会把内容挤出页面之外。',
      kind: ParagraphKind.quote,
    ),
    ParagraphBlock(
      text: '第一行代码\n第二行代码\n第三行代码\n第四行代码\n'
          '第五行代码\n第六行代码\n第七行代码',
      kind: ParagraphKind.code,
    ),
    ParagraphBlock(
      text: '代码块之后的正文，用来验证跨界后的排布是否仍然放得下内容。',
      kind: ParagraphKind.paragraph,
    ),
  ];

  /// 把某一页渲染出来，返回内容实际高度。
  Future<double> renderedHeight(
    WidgetTester tester,
    ReaderPage page,
    PaginationConfig config,
    ReaderSettings settings,
  ) async {
    tester.view.physicalSize = Size(config.pageWidth, config.pageHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderPageContentView(
          page: page,
          palette: ReadingPalette.all.first,
          settings: settings,
          onLongPressLine: (String _) async {},
        ),
      ),
    ));
    await tester.pump();

    final Finder content = find.byKey(ReaderPageContentView.contentKey);
    expect(content, findsOneWidget, reason: '内容容器应当渲染出来');
    return tester.getSize(content).height;
  }

  for (final double pageHeight in <double>[320, 400, 640]) {
    testWidgets('混合内容在 $pageHeight 高的页面上不溢出', (WidgetTester tester) async {
      final PaginationConfig config = configFor(pageHeight: pageHeight);
      final ReaderSettings settings = ReaderSettings.defaults();
      final List<ReaderPage> pages = Paginator().paginate(mixedContent, config);

      expect(pages, isNotEmpty);
      for (final ReaderPage page in pages) {
        if (page.isEmpty) {
          continue;
        }
        final double height = await renderedHeight(tester, page, config, settings);
        expect(
          height,
          lessThanOrEqualTo(config.availableHeight + 1.0),
          reason: '第 ${page.index} 页渲染高度 ${height.toStringAsFixed(1)} '
              '超过可用高度 ${config.availableHeight.toStringAsFixed(1)}',
        );
      }
    });
  }

  testWidgets('整章都是代码块时也不溢出（原来这里是重灾区）', (WidgetTester tester) async {
    final PaginationConfig config = configFor(pageHeight: 320);
    final ReaderSettings settings = ReaderSettings.defaults();
    final List<ParagraphBlock> blocks = <ParagraphBlock>[
      ParagraphBlock(
        text: List<String>.generate(20, (int i) => '代码行 ${i + 1}').join('\n'),
        kind: ParagraphKind.code,
      ),
    ];
    final List<ReaderPage> pages = Paginator().paginate(blocks, config);

    expect(pages.length, greaterThan(1), reason: '20 行代码在 320px 页面上必然要多页');
    for (final ReaderPage page in pages) {
      final double height = await renderedHeight(tester, page, config, settings);
      expect(
        height,
        lessThanOrEqualTo(config.availableHeight + 1.0),
        reason: '代码页 ${page.index} 溢出：${height.toStringAsFixed(1)} > '
            '${config.availableHeight.toStringAsFixed(1)}',
      );
    }
  });

  testWidgets('放大字号后依然不溢出', (WidgetTester tester) async {
    // 字号变大时行高与各类边距按比例放大，最容易暴露「忘了算某个占位」
    final PaginationConfig config = configFor(pageHeight: 400, fontSize: 26);
    final ReaderSettings settings = ReaderSettings.defaults().copyWith(fontScale: 26 / 18);
    final List<ReaderPage> pages = Paginator().paginate(mixedContent, config);

    for (final ReaderPage page in pages) {
      if (page.isEmpty) {
        continue;
      }
      final double height = await renderedHeight(tester, page, config, settings);
      expect(
        height,
        lessThanOrEqualTo(config.availableHeight + 1.0),
        reason: '放大字号后第 ${page.index} 页溢出：${height.toStringAsFixed(1)} > '
            '${config.availableHeight.toStringAsFixed(1)}',
      );
    }
  });

  test('分页计入的高度包含各行额外垂直占位', () {
    final PaginationConfig config = configFor();
    final List<ReaderPage> pages = Paginator().paginate(mixedContent, config);

    for (final ReaderPage page in pages) {
      double expected = 0;
      for (int i = 0; i < page.lines.length; i++) {
        final PageLine line = page.lines[i];
        // 段间距：段首行、且不是本页第一行
        if (i > 0 && line.isFirstLineOfParagraph) {
          expected += LineBox.paragraphSpacingPx(config.fontSize);
        }
        // 标题会按其级别放大字号，行高也要跟着放大
        final double scale = LineBox.fontScaleFactor(line.kind, line.headingLevel);
        expected += config.fontSize * scale * config.lineHeight +
            LineBox.extraVerticalPx(line.kind, config.fontSize);
      }
      // 每页的「预计占用」不该超过可用高度一行的余量
      expect(
        expected,
        lessThanOrEqualTo(config.availableHeight + config.lineHeightPx),
        reason: '第 ${page.index} 页预计占用 ${expected.toStringAsFixed(1)} 超出可用高度',
      );
    }
  });

  test('换行符不会被切成伪行，正文不丢字', () {
    // `getLineBoundary` 在 offset 落在 \n 上时会只返回换行符本身，
    // 伪行既多占一行高度，又会把真正的最后一行挤出循环（正文丢字）。
    const ParagraphBlock block = ParagraphBlock(
      text: '第一行代码\n第二行代码\n第三行代码\n第四行代码',
      kind: ParagraphKind.code,
    );
    final List<ReaderPage> pages = Paginator().paginate(<ParagraphBlock>[block], configFor());

    final List<String> rendered =
        pages.expand((ReaderPage p) => p.lines).map((PageLine l) => l.text).toList();
    expect(rendered, <String>['第一行代码', '第二行代码', '第三行代码', '第四行代码']);
    for (final String text in rendered) {
      expect(text.trim(), isNotEmpty, reason: '不该出现只含换行符的伪行');
    }
  });

  test('多行段落逐行切分后拼回原文（不丢字、不重复）', () {
    const ParagraphBlock block = ParagraphBlock(
      text: '甲甲甲\n乙乙乙\n丙丙丙\n丁丁丁\n戊戊戊',
      kind: ParagraphKind.paragraph,
    );
    final List<ReaderPage> pages = Paginator().paginate(<ParagraphBlock>[block], configFor());
    final String joined =
        pages.expand((ReaderPage p) => p.lines).map((PageLine l) => l.text).join('\n');

    expect(joined, block.text);
  });

  test('代码块的额外占位明显大于正文（说明确实在算它）', () {
    expect(
      LineBox.extraVerticalFactor(ParagraphKind.code),
      greaterThan(LineBox.extraVerticalFactor(ParagraphKind.quote)),
    );
    expect(
      LineBox.extraVerticalFactor(ParagraphKind.quote),
      greaterThan(LineBox.extraVerticalFactor(ParagraphKind.paragraph)),
    );
    expect(LineBox.extraVerticalFactor(ParagraphKind.paragraph), 0);
  });
}
