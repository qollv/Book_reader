import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/line_box.dart';
import 'package:novel_reader/core/pagination/page_line.dart';

/// 分页所需的排版参数。屏幕尺寸 + 用户外观设置共同决定。
class PaginationConfig {
  const PaginationConfig({
    required this.fontSize,
    required this.lineHeight,
    required this.pageWidth,
    required this.pageHeight,
    required this.horizontalMargin,
    required this.verticalMargin,
    this.fontFamily = 'system',
    this.textColor = const Color(0xFF1A1A1A),
  });

  final double fontSize;
  final double lineHeight; // 行距倍数
  final double pageWidth;
  final double pageHeight;
  final double horizontalMargin;
  final double verticalMargin;
  final String fontFamily;
  final Color textColor;

  double get lineHeightPx => fontSize * lineHeight;

  /// 段间距。走共享约定，与渲染端的实际间距保持同一份数字。
  double get paragraphSpacingPx => LineBox.paragraphSpacingPx(fontSize);
  double get firstLineIndentPx => fontSize * 2; // 首行缩进 2 字
  double get contentWidth => pageWidth - horizontalMargin * 2;
  double get availableHeight => pageHeight - verticalMargin * 2;

  /// 每页最多可容纳的行数（正文行高计）。
  int get maxLinesPerPage => availableHeight ~/ lineHeightPx;

  /// 用于缓存比对：任一参数变化都必须重新分页。
  String get cacheKey {
    return '$fontSize|$lineHeight|$pageWidth|$pageHeight|$horizontalMargin|$verticalMargin|$fontFamily';
  }
}

/// 智能分页引擎。
///
/// 规则：
/// - 用 TextPainter 逐段测行，行高与渲染端一致，分页结果即视觉结果；
/// - 所有行按「内容宽 - 首行缩进」测量，保证缩进后首行不溢出；
/// - 标题 keep-with-next：剩余空间放不下「标题 + 2 行正文」时换页；
/// - 孤行控制：拆页会只剩 1 行时，整段挪到下一页。
class Paginator {
  List<ReaderPage> paginate(List<ParagraphBlock> blocks, PaginationConfig config) {
    final _PagingState state = _PagingState(config: config);

    for (int blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final ParagraphBlock block = blocks[blockIndex];
      if (block.text.trim().isEmpty) {
        continue;
      }
      final List<_MeasuredLine> measured = _measureBlock(block, config);
      if (measured.isEmpty) {
        continue;
      }
      if (block.kind == ParagraphKind.heading) {
        _placeHeading(state, block, blockIndex, measured);
      } else {
        _placeBody(state, block, blockIndex, measured);
      }
    }
    return state.finish();
  }

  void _placeHeading(
    _PagingState state,
    ParagraphBlock block,
    int blockIndex,
    List<_MeasuredLine> measured,
  ) {
    // 标题自己也要占上下内边距，keep-with-next 的判定必须把它算进去，
    // 否则「标题 + 两行正文」看起来放得下、渲染出来最后一行被挤出页面
    final double headingHeight =
        _sumHeight(measured) + LineBox.extraVerticalPx(block.kind, state.config.fontSize);
    final double need = headingHeight + 2 * state.config.lineHeightPx;
    if (state.hasContent && state.usedHeight + need > state.config.availableHeight) {
      state.startNewPage();
    }
    state.appendLines(measured, block, blockIndex);
  }

  void _placeBody(
    _PagingState state,
    ParagraphBlock block,
    int blockIndex,
    List<_MeasuredLine> measured,
  ) {
    // 一行的真实成本 = 文字高度 + 该类型的额外垂直占位。
    // 段内各行类型相同，所以可以用同一个常量来估「还能放下几行」。
    final double perLineCost = state.config.lineHeightPx +
        LineBox.extraVerticalPx(block.kind, state.config.fontSize);
    final int maxLinesPerPage =
        math.max(1, (state.config.availableHeight / perLineCost).floor());

    int lineStart = 0;
    while (lineStart < measured.length) {
      final int remaining = measured.length - lineStart;
      final int fitCount = (state.config.availableHeight - state.usedHeight) ~/ perLineCost;

      if (fitCount >= remaining) {
        state.appendLines(measured.sublist(lineStart), block, blockIndex, lineStart);
        return;
      }
      if (fitCount < 2 || remaining - fitCount < 2) {
        // 拆页会留下孤行：整段挪到下一页
        if (state.hasContent) {
          state.startNewPage();
        }
        if (remaining <= maxLinesPerPage) {
          state.appendLines(measured.sublist(lineStart), block, blockIndex, lineStart);
          return;
        }
        // 段落比一页还长：按每页行数硬切
        state.appendLines(
          measured.sublist(lineStart, lineStart + maxLinesPerPage),
          block,
          blockIndex,
          lineStart,
        );
        state.startNewPage();
        lineStart += maxLinesPerPage;
        continue;
      }
      state.appendLines(measured.sublist(lineStart, lineStart + fitCount), block, blockIndex, lineStart);
      state.startNewPage();
      lineStart += fitCount;
    }
  }

  /// 测量宽度上留的安全余量（逻辑像素）。
  ///
  /// 分页器必须**高估**高度，绝不能低估：只要它认为某行放得下、
  /// 渲染时却换行了，页面就会溢出。
  ///
  /// 这不是理论担忧：字号放大到 26 时，一段 10 个汉字的文本宽度正好
  /// 等于可用宽度，分页测量判定为 1 行，渲染出来却是 2 行
  /// （渲染端的缩进是 `baseSize * 2` 参与浮点运算，宽度会差零点几像素）。
  /// 所以这里统一减掉 1 像素，把「恰好等于」的边界情况推到安全一侧。
  static const double _measurementSafetyInsetPx = 1.0;

  /// 单段测行：返回每行文本与高度。
  List<_MeasuredLine> _measureBlock(ParagraphBlock block, PaginationConfig config) {
    final TextStyle style = _styleFor(block, config);
    // 统一按减去首行缩进的宽度测量，缩进渲染后任何一行都不会溢出
    final double maxWidth = math.max(
      config.contentWidth - config.firstLineIndentPx - _measurementSafetyInsetPx,
      1,
    );

    final TextPainter painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: block.text, style: style),
    );
    painter.layout(maxWidth: maxWidth);
    final List<LineMetrics> metrics = painter.computeLineMetrics();
    final List<_MeasuredLine> lines = <_MeasuredLine>[];
    final String text = block.text;

    int start = 0;
    for (int i = 0; i < metrics.length && start < text.length; i++) {
      int end = _lineBoundaryEnd(painter, start, text.length);
      // 跳过「伪行」。
      //
      // `getLineBoundary` 在 offset 正好落在换行符上时，会把换行符本身
      // 当成一行返回（例如 `"甲\n乙"` 会切出 `"甲"`、`"\n"`、`"乙"` 三段）。
      // 这带来两个后果，都很难在单元测试里发现：
      //   1. 伪行是独立的一段，渲染时同样占一整行高度，页面凭空变长；
      //   2. 循环次数受 `metrics.length`（真实可视行数）限制，伪行会
      //      把真正的最后一行挤出循环 —— 表现为**正文丢字**。
      while (end < text.length && text.substring(start, end).trim().isEmpty) {
        start = end;
        end = _lineBoundaryEnd(painter, start, text.length);
      }
      if (start >= text.length) {
        break;
      }
      final String piece = text.substring(start, end);
      start = end;
      if (piece.trim().isEmpty) {
        // 空行不占页面高度（段间距已经负责分隔，不需要再空一行）
        continue;
      }
      lines.add(_MeasuredLine(text: piece, height: metrics[i].height));
    }
    painter.dispose();
    return lines;
  }

  /// 取 [start] 所在行的结束偏移，并保证一定向前推进（避免零宽行死循环）。
  int _lineBoundaryEnd(TextPainter painter, int start, int textLength) {
    final TextRange boundary = painter.getLineBoundary(TextPosition(offset: start));
    int end = boundary.end;
    if (end <= start) {
      end = start + 1;
    }
    return end > textLength ? textLength : end;
  }

  TextStyle _styleFor(ParagraphBlock block, PaginationConfig config) {
    // 字体缩放与字体族都取自共享约定：代码块渲染时用的是等宽字体，
    // 分页测量也必须用等宽字体，否则「量得下、渲染不下」
    final double fontSize =
        config.fontSize * LineBox.fontScaleFactor(block.kind, block.headingLevel);
    return TextStyle(
      fontSize: fontSize,
      height: config.lineHeight,
      color: config.textColor,
      fontFamily: LineBox.fontFamily(block.kind, config.fontFamily),
    );
  }

  double _sumHeight(List<_MeasuredLine> lines) {
    double total = 0;
    for (_MeasuredLine line in lines) {
      total += line.height;
    }
    return total;
  }
}

/// 分页过程状态：页列表 + 当前页缓冲 + 已用高度。
class _PagingState {
  _PagingState({required this.config});

  final PaginationConfig config;
  final List<ReaderPage> pages = <ReaderPage>[];
  final List<PageLine> current = <PageLine>[];
  double usedHeight = 0;

  bool get hasContent => current.isNotEmpty;

  void startNewPage() {
    if (current.isNotEmpty) {
      pages.add(ReaderPage(index: pages.length, lines: List<PageLine>.from(current)));
      current.clear();
      usedHeight = 0;
    }
  }

  void appendLines(List<_MeasuredLine> lines, ParagraphBlock block, int blockIndex, [int lineStart = 0]) {
    final double spacing = current.isEmpty ? 0 : config.paragraphSpacingPx;
    final double extra = LineBox.extraVerticalPx(block.kind, config.fontSize);
    for (int i = 0; i < lines.length; i++) {
      final int lineIndex = lineStart + i;
      current.add(PageLine(
        text: lines[i].text,
        paragraphIndex: blockIndex,
        lineIndex: lineIndex,
        isFirstLineOfParagraph: lineIndex == 0,
        kind: block.kind,
        headingLevel: block.headingLevel,
      ));
      // 文字高度之外还要加上该类型的边框/内边距占位，
      // 这段空间渲染时真实存在，分页时漏掉就会溢出页面
      usedHeight += lines[i].height + extra;
    }
    usedHeight += spacing;
  }

  List<ReaderPage> finish() {
    startNewPage();
    if (pages.isEmpty) {
      pages.add(const ReaderPage(index: 0, lines: <PageLine>[]));
    }
    return pages;
  }
}

/// 按锚点（章内段落下标 + 段内行下标）找所在页，找不到返回 0。
int findPageForAnchor(List<ReaderPage> pages, int paragraphIndex, int lineIndex) {
  for (ReaderPage page in pages) {
    for (PageLine line in page.lines) {
      if (line.paragraphIndex == paragraphIndex && line.lineIndex == lineIndex) {
        return page.index;
      }
    }
  }
  return 0;
}

class _MeasuredLine {
  const _MeasuredLine({required this.text, required this.height});

  final String text;
  final double height;
}
