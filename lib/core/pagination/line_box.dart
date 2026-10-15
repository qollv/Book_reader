import 'package:novel_reader/core/parsers/parsed_book.dart';

/// 行盒（line box）的几何约定。
///
/// **为什么要有这个文件**：分页器和渲染器是两个独立实现，但必须在
/// 「一行占多高」这件事上完全一致。原来分页器只按文字高度排，
/// 渲染器却给不同段落类型额外加了内外边距 —— 代码块最夸张：
/// 每行上下各 0.2 字号的 margin 加 0.5 字号的 padding，
/// 于是小屏上实测溢出 120px（渲染 400.4px / 可用 280px）。
///
/// 更隐蔽的一处：代码块渲染时把字体换成了等宽字体，而分页器仍按
/// 「比例字体 + 0.9 倍字号」测量 —— 字体度量不同，量出来放得下、
/// 渲染出来放不下。
///
/// 所以字体缩放、字体族、每行额外垂直占位、段间距这四件事全部集中在这里，
/// 分页器与渲染器都从这里取，改一处两边同时生效。
class LineBox {
  const LineBox._();

  /// 段与段之间的额外间距（基准字号的倍数）。
  static const double paragraphSpacingFactor = 0.5;

  /// 标题行上下内边距（单边，基准字号的倍数）。
  static const double headingPaddingVertical = 0.3;

  /// 引用行上下外边距（单边）。
  static const double quoteMarginVertical = 0.2;

  /// 代码行上下外边距（单边）。
  static const double codeMarginVertical = 0.2;

  /// 代码行四周内边距（底纹留白）。
  static const double codePadding = 0.5;

  /// 每行**除文字之外**要占的垂直空间（基准字号的倍数）。
  ///
  /// 由上面那些视觉常量推导，而不是各写一份 —— 否则改了 padding
  /// 忘了改这里，溢出就又回来了。
  static double extraVerticalFactor(ParagraphKind kind) {
    switch (kind) {
      case ParagraphKind.heading:
        return headingPaddingVertical * 2;
      case ParagraphKind.quote:
        return quoteMarginVertical * 2;
      case ParagraphKind.code:
        return codeMarginVertical * 2 + codePadding * 2;
      case ParagraphKind.paragraph:
        return 0;
    }
  }

  /// 字体缩放：标题按级别递减，最低不小于正文（1.0）。
  static double fontScaleFactor(ParagraphKind kind, int headingLevel) {
    if (kind != ParagraphKind.heading) {
      return 1.0;
    }
    final int level = headingLevel < 1 ? 1 : (headingLevel > 3 ? 3 : headingLevel);
    final double scale = 1.3 - 0.1 * (level - 1);
    return scale < 1.0 ? 1.0 : scale;
  }

  /// 行使用的字体族。代码块强制等宽 —— 字体度量不同，
  /// 分页测量必须跟着换，否则量的和渲染的不是同一件事。
  static String? fontFamily(ParagraphKind kind, String configured) {
    if (kind == ParagraphKind.code) {
      return 'monospace';
    }
    return configured == 'system' ? null : configured;
  }

  static double extraVerticalPx(ParagraphKind kind, double baseFontSize) =>
      extraVerticalFactor(kind) * baseFontSize;

  static double paragraphSpacingPx(double baseFontSize) =>
      paragraphSpacingFactor * baseFontSize;

  /// 一行的总占位：文字高度 + 额外垂直占位。
  static double lineCostPx(ParagraphKind kind, double textHeight, double baseFontSize) =>
      textHeight + extraVerticalPx(kind, baseFontSize);
}
