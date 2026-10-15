// 复现用测试 5：极端小高度下分页器死循环（分析工具生成）。
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';

void main() {
  final List<ParagraphBlock> blocks = <ParagraphBlock>[
    const ParagraphBlock(
      text: '第一段正文内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容。',
      kind: ParagraphKind.paragraph,
    ),
    const ParagraphBlock(
      text: '第二段正文内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容。',
      kind: ParagraphKind.paragraph,
    ),
  ];

  test('R15 maxLinesPerPage 在可用高度小于一行时归零', () {
    const PaginationConfig config = PaginationConfig(
      fontSize: 18,
      lineHeight: 1.8,
      pageWidth: 360,
      pageHeight: 60,
      horizontalMargin: 24,
      verticalMargin: 20,
    );
    print('R15 availableHeight=${config.availableHeight} lineHeightPx=${config.lineHeightPx} '
        'maxLinesPerPage=${config.maxLinesPerPage}');
  });

  test('R16 极端小高度调用 paginate', () {
    const PaginationConfig config = PaginationConfig(
      fontSize: 18,
      lineHeight: 1.8,
      pageWidth: 360,
      pageHeight: 60,
      horizontalMargin: 24,
      verticalMargin: 20,
    );
    print('R16 begin');
    final List<ReaderPage> pages = Paginator().paginate(blocks, config);
    print('R16 done pages=${pages.length}');
  });
}
