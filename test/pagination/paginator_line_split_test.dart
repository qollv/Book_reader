import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/block_metrics.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';

// 分页切行的两处缺陷回归测试。
//
// 1. 伪行导致正文丢字：`getLineBoundary` 在 offset 正好落在换行符上时，
//    会把换行符本身当成一行返回。伪行既多占一整行高度（`"\n"` 渲染出来是
//    64px），又因为循环次数受「真实可视行数」限制而把真正的最后一行挤出
//    循环 —— 也就是含换行的段落会**丢字**。
//    现有 `pagination_render_parity_test.dart` 覆盖不到：它是按
//    `page.lines` 重算高度，而丢字发生在更上游，重算的是已经丢过的那份数据；
//    其中名为「不因块边距而丢文本」的用例也只断言了 `totalLines > 0`。
//
// 2. 测量宽度缺少安全余量：分页测量恰好等于可用宽度时，分页判定「一行」，
//    渲染却会换行。下面第 3 个用例把这个不变量显式编码出来：
//    **分页切出的每一行，在渲染宽度下都必须只占一行**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PaginationConfig configFor({double pageHeight = 400, double fontSize = 18}) {
    return PaginationConfig(
      fontSize: fontSize,
      lineHeight: 1.8,
      pageWidth: 360,
      pageHeight: pageHeight,
      horizontalMargin: 24,
      verticalMargin: 20,
    );
  }

  List<String> allLineTexts(List<ReaderPage> pages) {
    return pages
        .expand((ReaderPage page) => page.lines)
        .map((PageLine line) => line.text)
        .toList(growable: false);
  }

  group('不丢字', () {
    test('换行符不会被切成伪行（代码块）', () {
      const ParagraphBlock block = ParagraphBlock(
        text: '第一行代码\n第二行代码\n第三行代码\n第四行代码',
        kind: ParagraphKind.code,
      );
      final List<String> rendered = allLineTexts(
        Paginator().paginate(<ParagraphBlock>[block], configFor()),
      );

      // 修复前这里会是 ['第一行代码', '\n', '第二行代码', ...]：
      // 既出现只含换行符的伪行，又丢掉最后一行
      expect(rendered, <String>['第一行代码', '第二行代码', '第三行代码', '第四行代码']);
    });

    test('多行段落逐行切分后拼回原文（不丢字、不重复）', () {
      const ParagraphBlock block = ParagraphBlock(
        text: '甲甲甲\n乙乙乙\n丙丙丙\n丁丁丁\n戊戊戊',
        kind: ParagraphKind.paragraph,
      );
      final String joined = allLineTexts(
        Paginator().paginate(<ParagraphBlock>[block], configFor()),
      ).join('\n');

      expect(joined, block.text);
    });

    test('长文本换行后仍能拼回全部字符', () {
      // 混合「显式换行」与「自动折行」，两条路径都必须不丢字符
      final ParagraphBlock block = ParagraphBlock(
        text: '第一段${'很长的内容' * 30}\n第二段${'更多内容' * 30}',
        kind: ParagraphKind.paragraph,
      );
      final String joined = allLineTexts(
        Paginator().paginate(<ParagraphBlock>[block], configFor(pageHeight: 320)),
      ).join();

      expect(joined.replaceAll('\n', ''), block.text.replaceAll('\n', ''));
    });

    test('不产生只含空白的行', () {
      const ParagraphBlock block = ParagraphBlock(
        text: '开头\n\n中间\n\n结尾',
        kind: ParagraphKind.paragraph,
      );
      final List<String> lines = allLineTexts(
        Paginator().paginate(<ParagraphBlock>[block], configFor()),
      );

      for (final String text in lines) {
        expect(text.trim(), isNotEmpty, reason: '出现空白行: ${text.codeUnits}');
      }
      expect(lines, <String>['开头', '中间', '结尾']);
    });
  });

  group('每一行分页都对应渲染时的一行', () {
    /// 渲染端的盒模型（与 `_PageContentView._buildPiece` 同源）：
    /// 代码块等宽字体、段首行减缩进，其余取整宽。
    TextStyle rendererStyle(PageLine line, PaginationConfig config) {
      return TextStyle(
        fontSize: BlockMetrics.fontSizeFor(line.kind, line.headingLevel, config.fontSize),
        height: config.lineHeight,
        fontFamily: line.kind == ParagraphKind.code
            ? 'monospace'
            : (config.fontFamily == 'system' ? null : config.fontFamily),
      );
    }

    double rendererWidth(PageLine line, PaginationConfig config) {
      return line.isFirstLineOfParagraph
          ? config.contentWidth - config.firstLineIndentPx
          : config.contentWidth;
    }

    int renderedLineCount(PageLine line, PaginationConfig config) {
      final TextPainter painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(text: line.text, style: rendererStyle(line, config)),
      );
      painter.layout(maxWidth: rendererWidth(line, config));
      final int count = painter.computeLineMetrics().length;
      painter.dispose();
      return count;
    }

    void expectEveryLineRendersAsOne(
      String name,
      List<ParagraphBlock> blocks,
      PaginationConfig config,
    ) {
      final List<ReaderPage> pages = Paginator().paginate(blocks, config);
      for (final ReaderPage page in pages) {
        for (final PageLine line in page.lines) {
          expect(
            renderedLineCount(line, config),
            1,
            reason: '$name 页${page.index}：「${line.text}」被分页当成一行，'
                '但在渲染宽度下会折行，页面会溢出',
          );
        }
      }
    }

    test('正文/标题/引用/代码，多种页高与字号', () {
      final Map<String, List<ParagraphBlock>> cases = <String, List<ParagraphBlock>>{
        '正文': <ParagraphBlock>[
          ParagraphBlock(text: '正文一段${'内容' * 40}', kind: ParagraphKind.paragraph),
          ParagraphBlock(text: '正文二段${'内容' * 40}', kind: ParagraphKind.paragraph),
        ],
        '标题': <ParagraphBlock>[
          ParagraphBlock(
              text: '第一章 起风了', kind: ParagraphKind.heading, headingLevel: 1),
          ParagraphBlock(
              text: '第二章 落雨了', kind: ParagraphKind.heading, headingLevel: 2),
        ],
        '引用': <ParagraphBlock>[
          ParagraphBlock(text: '引用一行${'内容' * 40}', kind: ParagraphKind.quote),
        ],
        '代码': <ParagraphBlock>[
          ParagraphBlock(text: '代码行一\n代码行二\n代码行三', kind: ParagraphKind.code),
          ParagraphBlock(text: List<String>.filled(60, 'i').join(), kind: ParagraphKind.code),
          ParagraphBlock(text: 'W' * 60, kind: ParagraphKind.code),
        ],
      };

      for (final MapEntry<String, List<ParagraphBlock>> entry in cases.entries) {
        for (final double height in <double>[320, 400, 640]) {
          for (final double fontSize in <double>[18, 26]) {
            expectEveryLineRendersAsOne(
              '${entry.key}/h=$height/fs=$fontSize',
              entry.value,
              configFor(pageHeight: height, fontSize: fontSize),
            );
          }
        }
      }
    });

    test('文本宽度恰好等于可用宽度时也不会被误判为一行', () {
      // 10 个汉字 × 26px = 260px，正好等于「内容宽 312 − 缩进 52」。
      // 没有测量余量时，分页会判成 1 行，而渲染端因浮点误差折成 2 行。
      const ParagraphBlock block =
          ParagraphBlock(text: '这是正文第一段用来', kind: ParagraphKind.paragraph);
      final PaginationConfig config = configFor(fontSize: 26);

      expectEveryLineRendersAsOne('边界宽度', <ParagraphBlock>[block], config);
    });

    test('等宽字体的字宽差异不会导致误判', () {
      // 小写 i 在比例字体里很窄、在等宽字体里与其它字符同宽：
      // 分页若按比例字体测、渲染按等宽画，长串 i 就会多折一行。
      const ParagraphBlock block = ParagraphBlock(
        text: 'iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii',
        kind: ParagraphKind.code,
      );

      expectEveryLineRendersAsOne('等宽字体', <ParagraphBlock>[block], configFor());
    });
  });
}
