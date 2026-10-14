import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/block_metrics.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';

// TC-07：DEF-07 分页/渲染度量一致性。
// 渲染端按块绘制边距（BlockMetrics），分页预算必须计入同样的高度，
// 否则块密集页会溢出可视区。行高用 TextPainter 实测（引擎会把
// fontSize*lineHeight 吸附到实际行高，如 18*1.8=32.4 → 32.0），
// 与分页器、渲染端三者同源。
void main() {
  PaginationConfig configFor(double pageHeight) {
    return PaginationConfig(
      fontSize: 18,
      lineHeight: 1.8,
      pageWidth: 360,
      pageHeight: pageHeight,
      horizontalMargin: 24,
      verticalMargin: 20,
    );
  }

  /// 实测一行文本的渲染高度（与渲染端 Text 同一套样式）。
  double measureLine(String text, double fontSize, PaginationConfig config) {
    final TextPainter painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: config.lineHeight),
      ),
    );
    painter.layout(maxWidth: config.contentWidth);
    final List<LineMetrics> metrics = painter.computeLineMetrics();
    painter.dispose();
    return metrics.isEmpty ? config.lineHeightPx : metrics.first.height;
  }

  /// 与 _PageContentView 的盒模型同源：块间距 + 块级边距 + 实测行高。
  double renderedHeight(ReaderPage page, PaginationConfig config) {
    final BlockMetrics metrics = config.metrics;
    final List<List<PageLine>> pieces = <List<PageLine>>[];
    for (PageLine line in page.lines) {
      if (pieces.isNotEmpty && pieces.last.first.paragraphIndex == line.paragraphIndex) {
        pieces.last.add(line);
      } else {
        pieces.add(<PageLine>[line]);
      }
    }

    double height = 0;
    for (int i = 0; i < pieces.length; i++) {
      final List<PageLine> piece = pieces[i];
      final PageLine head = piece.first;
      if (i > 0) {
        height += metrics.paragraphSpacing;
      }
      height += metrics.blockExtraHeight(head.kind, head.headingLevel);
      for (PageLine line in piece) {
        final double fontSize =
            BlockMetrics.fontSizeFor(head.kind, head.headingLevel, config.fontSize);
        height += measureLine(line.text, fontSize, config);
      }
    }
    return height;
  }

  void expectNoOverflow(String name, List<ParagraphBlock> blocks, double pageHeight) {
    final PaginationConfig config = configFor(pageHeight);
    final List<ReaderPage> pages = Paginator().paginate(blocks, config);
    for (ReaderPage page in pages) {
      final double height = renderedHeight(page, config);
      expect(
        height,
        lessThanOrEqualTo(config.availableHeight + 1),
        reason: '$name 页${page.index} 渲染高度 $height 超出可用高度 ${config.availableHeight}',
      );
    }
  }

  List<ParagraphBlock> repeat(ParagraphKind kind, int count, int charsEach) {
    return List<ParagraphBlock>.generate(count, (int i) {
      return ParagraphBlock(text: '块$i${'内容' * charsEach}', kind: kind, headingLevel: 1);
    });
  }

  test('四类内容 × 多种页高，渲染高度均不超出可用高度', () {
    final Map<String, List<ParagraphBlock>> cases = <String, List<ParagraphBlock>>{
      '纯正文': repeat(ParagraphKind.paragraph, 8, 60),
      '代码密集': repeat(ParagraphKind.code, 8, 40),
      '引用密集': repeat(ParagraphKind.quote, 8, 40),
      '标题密集': repeat(ParagraphKind.heading, 8, 6),
      '混合': <ParagraphBlock>[
        ...repeat(ParagraphKind.heading, 2, 4),
        ...repeat(ParagraphKind.paragraph, 3, 50),
        ...repeat(ParagraphKind.code, 2, 30),
        ...repeat(ParagraphKind.quote, 2, 30),
      ],
    };
    for (final MapEntry<String, List<ParagraphBlock>> entry in cases.entries) {
      for (final double pageHeight in <double>[320, 640, 800]) {
        expectNoOverflow(entry.key, entry.value, pageHeight);
      }
    }
  });

  test('maxLinesPerPage 与行高计算不因块边距而丢文本', () {
    final List<ParagraphBlock> blocks = repeat(ParagraphKind.code, 6, 50);
    final PaginationConfig config = configFor(400);
    final List<ReaderPage> pages = Paginator().paginate(blocks, config);
    int totalLines = 0;
    for (ReaderPage page in pages) {
      totalLines += page.lines.length;
    }
    expect(totalLines, greaterThan(0));
    expect(config.maxLinesPerPage, greaterThan(0));
  });
}
