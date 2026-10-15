// 复现用测试 3：分页结果 vs 渲染结果的高度一致性（分析工具生成）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';

/// 与 lib/ui/pages/reader_screen.dart 的 _PageContentView/_buildLine 同构的复刻：
/// 同一份样式与内边距数值。
class RenderProbe extends StatelessWidget {
  const RenderProbe({super.key, required this.page, required this.config, required this.key2});

  final ReaderPage page;
  final PaginationConfig config;
  final GlobalKey key2;

  @override
  Widget build(BuildContext context) {
    final double baseSize = config.fontSize;
    final TextStyle style = TextStyle(
      fontSize: baseSize,
      height: config.lineHeight,
      color: config.textColor,
      fontFamily: config.fontFamily == 'system' ? null : config.fontFamily,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: config.horizontalMargin,
        vertical: config.verticalMargin,
      ),
      child: Column(
        key: key2,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: page.lines.map((PageLine line) {
          if (line.isHeading) {
            final double scale = 1.3 - 0.1 * (line.headingLevel - 1);
            return Padding(
              padding: EdgeInsets.symmetric(vertical: baseSize * 0.3),
              child: Text(line.text,
                  textAlign: TextAlign.center,
                  style: style.copyWith(fontSize: baseSize * scale, fontWeight: FontWeight.bold)),
            );
          }
          if (line.kind == ParagraphKind.quote) {
            return Container(
              margin: EdgeInsets.symmetric(vertical: baseSize * 0.2),
              padding: EdgeInsets.only(left: baseSize * 0.8),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Colors.grey, width: 2)),
              ),
              child: Text(line.text, style: style),
            );
          }
          if (line.kind == ParagraphKind.code) {
            return Container(
              margin: EdgeInsets.symmetric(vertical: baseSize * 0.2),
              padding: EdgeInsets.all(baseSize * 0.5),
              color: Colors.black12,
              child: Text(line.text, style: style.copyWith(fontFamily: 'monospace')),
            );
          }
          if (line.isFirstLineOfParagraph) {
            return Padding(
              padding: EdgeInsets.only(left: baseSize * 2),
              child: Text(line.text, style: style),
            );
          }
          return Text(line.text, style: style);
        }).toList(),
      ),
    );
  }
}

void main() {
  const PaginationConfig config = PaginationConfig(
    fontSize: 18,
    lineHeight: 1.8,
    pageWidth: 360,
    pageHeight: 640,
    horizontalMargin: 24,
    verticalMargin: 20,
  );

  testWidgets('R12 含标题的页：渲染高度是否超出可排版高度', (WidgetTester tester) async {
    final List<ParagraphBlock> blocks = <ParagraphBlock>[
      const ParagraphBlock(text: '正文段落一，内容足够长以占据若干行，重复内容内容内容内容内容内容内容内容内容内容内容内容。', kind: ParagraphKind.paragraph),
      const ParagraphBlock(text: '第一章 起风了', kind: ParagraphKind.heading, headingLevel: 1),
      const ParagraphBlock(text: '正文段落二，继续占据若干行，重复内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容。', kind: ParagraphKind.paragraph),
      const ParagraphBlock(text: '引用一行', kind: ParagraphKind.quote),
      const ParagraphBlock(text: 'code line 1', kind: ParagraphKind.code),
      const ParagraphBlock(text: '正文段落三，重复内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容。', kind: ParagraphKind.paragraph),
    ];
    final List<ReaderPage> pages = Paginator().paginate(blocks, config);
    print('R12 pages=${pages.length} availableHeight=${config.availableHeight}');

    for (final ReaderPage page in pages) {
      final GlobalKey key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: config.pageWidth,
            height: config.pageHeight,
            child: RenderProbe(page: page, config: config, key2: key),
          ),
        ),
      ));
      await tester.pump();
      final Size content = tester.getSize(find.byKey(key));
      final bool hasHeading = page.lines.any((PageLine l) => l.isHeading);
      final bool hasQuote = page.lines.any((PageLine l) => l.kind == ParagraphKind.quote);
      final bool hasCode = page.lines.any((PageLine l) => l.kind == ParagraphKind.code);
      print('R12 page#${page.index} lines=${page.lines.length} heading=$hasHeading quote=$hasQuote code=$hasCode '
          'renderedContentHeight=${content.height.toStringAsFixed(1)} '
          'budget=${config.availableHeight.toStringAsFixed(1)} '
          'overflow=${(content.height - config.availableHeight).toStringAsFixed(1)}');
    }
  });

  testWidgets('R13 纯正文页：渲染高度是否与预算一致', (WidgetTester tester) async {
    final List<ParagraphBlock> blocks = List<ParagraphBlock>.generate(
      12,
      (int i) => ParagraphBlock(
        text: '第$i段正文内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容。',
        kind: ParagraphKind.paragraph,
      ),
    );
    final List<ReaderPage> pages = Paginator().paginate(blocks, config);
    for (final ReaderPage page in pages) {
      final GlobalKey key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: config.pageWidth,
            height: config.pageHeight,
            child: RenderProbe(page: page, config: config, key2: key),
          ),
        ),
      ));
      await tester.pump();
      final Size content = tester.getSize(find.byKey(key));
      print('R13 page#${page.index} lines=${page.lines.length} '
          'rendered=${content.height.toStringAsFixed(1)} budget=${config.availableHeight.toStringAsFixed(1)} '
          'overflow=${(content.height - config.availableHeight).toStringAsFixed(1)}');
    }
  });
}
