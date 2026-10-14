import 'package:novel_reader/core/parsers/parsed_book.dart';

/// 分页与渲染共享的块级度量。
///
/// 分页预算和 UI 渲染必须引用同一套常量，否则"分页即视觉"失效——
/// 曾因渲染端按行绘制块级内外边距导致代码密集页溢出 120px。
class BlockMetrics {
  const BlockMetrics(this.fontSize);

  final double fontSize;

  /// 段间距：块与块之间的垂直间距（页面首块不画）。
  double get paragraphSpacing => fontSize * 0.5;

  /// 标题字号相对正文的倍数。
  static double headingScale(int level) => 1.3 - 0.1 * (level - 1);

  /// 代码块字号相对正文的倍数。
  static double codeScale = 0.9;

  /// 块的实际字号：分页测量、渲染、测试必须同源。
  static double fontSizeFor(ParagraphKind kind, int headingLevel, double base) {
    if (kind == ParagraphKind.heading) {
      return base * headingScale(headingLevel);
    }
    if (kind == ParagraphKind.code) {
      return base * codeScale;
    }
    return base;
  }

  /// 标题块上下内边距。
  double headingPadding(int level) => fontSize * headingScale(level) * 0.3;

  /// 引用块左右缩进与上下外边距。
  double get quoteIndent => fontSize * 2;
  double get quoteMargin => fontSize * 0.2;

  /// 代码块内外边距。
  double get codeMargin => fontSize * 0.2;
  double get codePadding => fontSize * 0.5;

  /// 一个块（片段）占据的块级额外高度，不含行高本身。
  double blockExtraHeight(ParagraphKind kind, int headingLevel) {
    switch (kind) {
      case ParagraphKind.heading:
        return headingPadding(headingLevel) * 2;
      case ParagraphKind.quote:
        return quoteMargin * 2;
      case ParagraphKind.code:
        return (codeMargin + codePadding) * 2;
      case ParagraphKind.paragraph:
        return 0;
    }
  }
}
