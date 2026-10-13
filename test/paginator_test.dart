import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';

List<ParagraphBlock> _longParagraphs(int count, int charsEach) {
  return List<ParagraphBlock>.generate(count, (int i) {
    return ParagraphBlock(text: '第${i}段' + '内容' * charsEach, kind: ParagraphKind.paragraph);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PaginationConfig smallConfig() {
    return const PaginationConfig(
      fontSize: 18,
      lineHeight: 1.8,
      pageWidth: 360,
      pageHeight: 400,
      horizontalMargin: 24,
      verticalMargin: 20,
    );
  }

  test('empty input produces one empty page', () {
    final List<ReaderPage> pages = Paginator().paginate(<ParagraphBlock>[], smallConfig());
    expect(pages, hasLength(1));
    expect(pages.first.isEmpty, isTrue);
  });

  test('no text is lost across pages', () {
    final List<ParagraphBlock> blocks = _longParagraphs(6, 120);
    final List<ReaderPage> pages = Paginator().paginate(blocks, smallConfig());
    expect(pages.length, greaterThan(1));

    final Set<String> seen = <String>{};
    int totalLines = 0;
    for (ReaderPage page in pages) {
      for (PageLine line in page.lines) {
        seen.add('${line.paragraphIndex}:${line.lineIndex}');
        totalLines++;
      }
    }
    // 每个段落的每一行都恰好出现一次
    int expectedLines = 0;
    for (int i = 0; i < blocks.length; i++) {
      expectedLines += Paginator().paginate(<ParagraphBlock>[blocks[i]], smallConfig()).fold(0, (int sum, ReaderPage p) => sum + p.lines.length);
    }
    expect(totalLines, expectedLines);
    expect(seen, hasLength(totalLines));
  });

  test('every page fits the available height', () {
    final List<ParagraphBlock> blocks = _longParagraphs(4, 200);
    final PaginationConfig config = smallConfig();
    final List<ReaderPage> pages = Paginator().paginate(blocks, config);
    for (ReaderPage page in pages) {
      double height = 0;
      for (PageLine line in page.lines) {
        height += config.lineHeightPx;
      }
      expect(height, lessThanOrEqualTo(config.availableHeight + config.lineHeightPx));
    }
  });

  test('heading is never the last line of a page', () {
    final List<ParagraphBlock> blocks = <ParagraphBlock>[
      ..._longParagraphs(2, 150),
      const ParagraphBlock(text: '第九章 转折', kind: ParagraphKind.heading),
      ..._longParagraphs(2, 150),
    ];
    final List<ReaderPage> pages = Paginator().paginate(blocks, smallConfig());
    for (ReaderPage page in pages) {
      if (page.lines.length >= 2) {
        expect(page.lines.last.isHeading, isFalse);
      }
    }
  });

  test('findPageForAnchor locates the anchor page', () {
    final List<ParagraphBlock> blocks = _longParagraphs(3, 100);
    final List<ReaderPage> pages = Paginator().paginate(blocks, smallConfig());
    final PageLine target = pages.first.lines.first;
    expect(findPageForAnchor(pages, target.paragraphIndex, target.lineIndex), 0);
  });
}
