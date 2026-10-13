import 'package:novel_reader/core/parsers/parsed_book.dart';

/// 一页中的一行渲染数据。
///
/// 记录锚点（章内段落下标 + 段内行下标）供进度恢复与书签定位。
class PageLine {
  const PageLine({
    required this.text,
    required this.paragraphIndex,
    required this.lineIndex,
    required this.isFirstLineOfParagraph,
    required this.kind,
    required this.headingLevel,
  });

  final String text;
  final int paragraphIndex;
  final int lineIndex;
  final bool isFirstLineOfParagraph;
  final ParagraphKind kind;
  final int headingLevel;

  bool get isHeading => kind == ParagraphKind.heading;
}

/// 一页：行列表 + 页号。
class ReaderPage {
  const ReaderPage({required this.index, required this.lines});

  final int index;
  final List<PageLine> lines;

  bool get isEmpty => lines.isEmpty;

  /// 页首锚点：本章第一段第一行。
  int get anchorParagraph => lines.isEmpty ? 0 : lines.first.paragraphIndex;

  int get anchorLine => lines.isEmpty ? 0 : lines.first.lineIndex;
}
