import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/block_metrics.dart';
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
  double get firstLineIndentPx => fontSize * 2; // 首行缩进 2 字
  double get contentWidth => pageWidth - horizontalMargin * 2;
  double get availableHeight => pageHeight - verticalMargin * 2;

  /// 块级度量与渲染端同源（BlockMetrics）。
  BlockMetrics get metrics => BlockMetrics(fontSize);

  /// 每页最多可容纳的行数（正文行高计）。
  /// 页面过矮时至少保留 1 行，否则硬切分支步进为 0 会死循环。
  int get maxLinesPerPage => math.max(1, availableHeight ~/ lineHeightPx);

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
    final double headingHeight = _sumHeight(measured);
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
    final BlockMetrics metrics = state.config.metrics;
    final double blockExtra = metrics.blockExtraHeight(block.kind, block.headingLevel);
    // 块内所有行同样式，行高一致，取实测值（引擎会吸附 fontSize*lineHeight）
    final double lineHeight = measured.first.height;

    int lineStart = 0;
    while (lineStart < measured.length) {
      final int startBefore = lineStart;
      final int remaining = measured.length - lineStart;
      // 放当前页要先扣除段间距与块级边距，再按实测行高算容量——
      // 少扣任何一项都会让拆页后的页面溢出（曾因此代码密集页超 120px）。
      final double overhead = (state.hasContent ? metrics.paragraphSpacing : 0) + blockExtra;
      final double budget = state.config.availableHeight - state.usedHeight - overhead;
      final int fitCount = budget ~/ lineHeight;

      if (fitCount >= remaining) {
        state.appendLines(measured.sublist(lineStart), block, blockIndex, lineStart);
        return;
      }
      if (fitCount < 2 || remaining - fitCount < 2) {
        // 拆页会留下孤行：整段挪到下一页
        if (state.hasContent) {
          state.startNewPage();
        }
        // 空页容量：扣除块级边距后至少放 1 行
        final int freshCapacity = math.max(1, (state.config.availableHeight - blockExtra) ~/ lineHeight);
        if (remaining <= freshCapacity) {
          state.appendLines(measured.sublist(lineStart), block, blockIndex, lineStart);
          return;
        }
        // 段落比一页还长：按空页容量硬切
        state.appendLines(
          measured.sublist(lineStart, lineStart + freshCapacity),
          block,
          blockIndex,
          lineStart,
        );
        state.startNewPage();
        lineStart += freshCapacity;
        continue;
      }
      state.appendLines(measured.sublist(lineStart, lineStart + fitCount), block, blockIndex, lineStart);
      state.startNewPage();
      lineStart += fitCount;
      // 死循环防护：任何一条路径都必须推进 lineStart
      assert(lineStart > startBefore, 'pagination must make progress');
    }
  }

  /// 单段测行：返回每行文本与高度。
  List<_MeasuredLine> _measureBlock(ParagraphBlock block, PaginationConfig config) {
    final TextStyle style = _styleFor(block, config);
    // 统一按减去首行缩进的宽度测量，缩进渲染后任何一行都不会溢出
    final double maxWidth = math.max(config.contentWidth - config.firstLineIndentPx, 1);

    final TextPainter painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: block.text, style: style),
    );
    painter.layout(maxWidth: maxWidth);
    final List<LineMetrics> metrics = painter.computeLineMetrics();
    final List<_MeasuredLine> lines = <_MeasuredLine>[];

    // 新版 LineMetrics 不再暴露 start/end，用 getLineBoundary 逐行取区间
    int start = 0;
    for (int i = 0; i < metrics.length && start < block.text.length; i++) {
      final TextRange boundary = painter.getLineBoundary(TextPosition(offset: start));
      int end = boundary.end;
      if (end <= start) {
        end = start + 1; // 防御零宽行（如纯空白）导致死循环
      }
      if (end > block.text.length) {
        end = block.text.length;
      }
      lines.add(_MeasuredLine(text: block.text.substring(start, end), height: metrics[i].height));
      start = end;
    }
    painter.dispose();
    return lines;
  }

  TextStyle _styleFor(ParagraphBlock block, PaginationConfig config) {
    return TextStyle(
      fontSize: BlockMetrics.fontSizeFor(block.kind, block.headingLevel, config.fontSize),
      height: config.lineHeight,
      color: config.textColor,
      fontFamily: config.fontFamily == 'system' ? null : config.fontFamily,
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

  /// 把一段（或段的一片）的行追加到当前页。
  /// 高度预算与渲染端严格同源：段间距 + 块级内外边距（BlockMetrics）+ 行高。
  void appendLines(List<_MeasuredLine> lines, ParagraphBlock block, int blockIndex, [int lineStart = 0]) {
    final BlockMetrics metrics = config.metrics;
    final double spacing = current.isEmpty ? 0 : metrics.paragraphSpacing;
    usedHeight += spacing;
    usedHeight += metrics.blockExtraHeight(block.kind, block.headingLevel);
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
      usedHeight += lines[i].height;
    }
  }

  List<ReaderPage> finish() {
    startNewPage();
    if (pages.isEmpty) {
      pages.add(const ReaderPage(index: 0, lines: <PageLine>[]));
    }
    return pages;
  }
}

/// 按锚点（章内段落下标 + 段内行下标）找所在页。
///
/// 精确锚点找不到时（如改字号后重排版）回退到最近邻页：
/// 取第一个段落下标 >= 目标的页；目标超出全文则取最后一页。
/// 不再静默返回第 0 页——那会让用户以为跳转坏了。
int findPageForAnchor(List<ReaderPage> pages, int paragraphIndex, int lineIndex) {
  for (ReaderPage page in pages) {
    for (PageLine line in page.lines) {
      if (line.paragraphIndex == paragraphIndex && line.lineIndex == lineIndex) {
        return page.index;
      }
    }
  }
  for (ReaderPage page in pages) {
    for (PageLine line in page.lines) {
      if (line.paragraphIndex >= paragraphIndex) {
        return page.index;
      }
    }
  }
  return pages.isEmpty ? 0 : pages.length - 1;
}

class _MeasuredLine {
  const _MeasuredLine({required this.text, required this.height});

  final String text;
  final double height;
}
