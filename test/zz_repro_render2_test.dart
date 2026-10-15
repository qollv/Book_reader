// 复现用测试 4：标题/代码块内边距未计入分页预算导致页内容溢出（分析工具生成）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';

class RenderProbe extends StatelessWidget {
  const RenderProbe({super.key, required this.page, required this.config, required this.probeKey});

  final ReaderPage page;
  final PaginationConfig config;
  final GlobalKey probeKey;

  @override
  Widget build(BuildContext context) {
    final double baseSize = config.fontSize;
    final TextStyle style = TextStyle(
      fontSize: baseSize,
      height: config.lineHeight,
      color: config.textColor,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: config.horizontalMargin,
        vertical: config.verticalMargin,
      ),
      child: Column(
        key: probeKey,
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
            return Padding(padding: EdgeInsets.only(left: baseSize * 2), child: Text(line.text, style: style));
          }
          return Text(line.text, style: style);
        }).toList(),
      ),
    );
  }
}

List<ParagraphBlock> mixedBlocks() {
  final List<ParagraphBlock> blocks = <ParagraphBlock>[];
  for (int i = 0; i < 8; i++) {
    blocks.add(ParagraphBlock(text: '第$i章 标题行', kind: ParagraphKind.heading, headingLevel: 1));
    blocks.add(ParagraphBlock(text: '一句话正文$i。', kind: ParagraphKind.paragraph));
    blocks.add(ParagraphBlock(text: 'code line $i', kind: ParagraphKind.code));
    blocks.add(ParagraphBlock(text: '另一句话正文$i。', kind: ParagraphKind.paragraph));
  }
  return blocks;
}

/// 密集的代码块 / 引用块：相邻块之间只有 0.5 字行距预算，但渲染端有块内边距。
List<ParagraphBlock> codeHeavyBlocks() {
  return List<ParagraphBlock>.generate(
    8,
    (int i) => ParagraphBlock(text: 'code line $i', kind: ParagraphKind.code),
  );
}

List<ParagraphBlock> quoteHeavyBlocks() {
  return List<ParagraphBlock>.generate(
    10,
    (int i) => ParagraphBlock(text: '引用第$i行', kind: ParagraphKind.quote),
  );
}

void main() {
  for (final String name in <String>['mixed', 'code', 'quote']) {
    for (final double pageHeight in <double>[320, 640]) {
      testWidgets('R14 $name pageHeight=$pageHeight 溢出测量', (WidgetTester tester) async {
        final PaginationConfig config = PaginationConfig(
          fontSize: 18,
          lineHeight: 1.8,
          pageWidth: 360,
          pageHeight: pageHeight,
          horizontalMargin: 24,
          verticalMargin: 20,
        );
        final List<ParagraphBlock> blocks = name == 'mixed' ? mixedBlocks() : (name == 'code' ? codeHeavyBlocks() : quoteHeavyBlocks());
        final List<ReaderPage> pages = Paginator().paginate(blocks, config);
        double worst = 0;
        for (final ReaderPage page in pages) {
          final GlobalKey key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: config.pageWidth,
                height: config.pageHeight,
                child: RenderProbe(page: page, config: config, probeKey: key),
              ),
            ),
          ));
          await tester.pump();
          final double rendered = tester.getSize(find.byKey(key)).height;
          final double overflow = rendered - config.availableHeight;
          worst = overflow > worst ? overflow : worst;
          if (overflow > 0) {
            print('R14 $name h=$pageHeight page#${page.index} lines=${page.lines.length} '
                'rendered=${rendered.toStringAsFixed(1)} budget=${config.availableHeight.toStringAsFixed(1)} '
                'overflow=${overflow.toStringAsFixed(1)} '
                'headings=${page.lines.where((PageLine l) => l.isHeading).length} '
                'codes=${page.lines.where((PageLine l) => l.kind == ParagraphKind.code).length} '
                'quotes=${page.lines.where((PageLine l) => l.kind == ParagraphKind.quote).length}');
          }
        }
        print('R14 $name h=$pageHeight pages=${pages.length} worstOverflow=${worst.toStringAsFixed(1)}');
      });
    }
  }
}
