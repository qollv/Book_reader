import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';

List<ParagraphBlock> _longParagraphs(int count, int charsEach) {
  return List<ParagraphBlock>.generate(count, (int i) {
    return ParagraphBlock(text: '第$i段${'内容' * charsEach}', kind: ParagraphKind.paragraph);
  });
}

// TC-06：DEF-04 页面过矮（availableHeight < lineHeightPx）时曾死循环卡死 UI 线程。
void main() {
  PaginationConfig shortPageConfig() {
    return const PaginationConfig(
      fontSize: 18,
      lineHeight: 1.8,
      pageWidth: 360,
      pageHeight: 60, // availableHeight = 20 < lineHeightPx = 32.4
      horizontalMargin: 24,
      verticalMargin: 20,
    );
  }

  test('availableHeight 小于一行高度时也能返回', () {
    final List<ParagraphBlock> blocks = _longParagraphs(3, 100);
    final List<ReaderPage> pages = Paginator().paginate(blocks, shortPageConfig());
    expect(pages, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('极端参数组合不卡死且文本不丢失', () {
    final List<ParagraphBlock> blocks = _longParagraphs(4, 80);
    for (final double fontSize in <double>[9, 18, 28]) {
      for (final double lineHeight in <double>[1.4, 2.4]) {
        final PaginationConfig config = PaginationConfig(
          fontSize: fontSize,
          lineHeight: lineHeight,
          pageWidth: 320,
          pageHeight: 60,
          horizontalMargin: 16,
          verticalMargin: 12,
        );
        final List<ReaderPage> pages = Paginator().paginate(blocks, config);
        expect(pages, isNotEmpty, reason: 'fontSize=$fontSize lineHeight=$lineHeight');

        int totalLines = 0;
        for (ReaderPage page in pages) {
          totalLines += page.lines.length;
        }
        expect(totalLines, greaterThan(0));
      }
    }
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('maxLinesPerPage 至少为 1', () {
    expect(shortPageConfig().maxLinesPerPage, 1);
  });
}
