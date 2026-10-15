import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/core/parsers/markdown_parser.dart';

/// 行内 Markdown 剥离的回归测试。
///
/// 根因：`String.replaceAll` 的替换串是**字面量**，不支持 `$1` 反向引用
/// （只有 `replaceAllMapped` 支持）。原实现整段用 `replaceAll(re, r'$1')`，
/// 于是每个行内语法都被替换成字面量 `$1` / `$1$2` 混进正文：
/// `**粗体**` → `$1`。这份用例同时钉住「不许出现 $1」和
/// 「snake_case 不能被当成斜体吃掉」。
void main() {
  /// 任何输出里都不该出现反向引用残留。
  void expectNoPlaceholderLeak(String output) {
    for (final String leak in <String>['\$1', '\$2', '\$0']) {
      expect(output.contains(leak), isFalse, reason: '输出里泄漏了替换占位符: "$output"');
    }
  }

  group('行内语法剥离', () {
    test('粗体', () {
      final String out = MarkdownParser.stripInline('**粗体** 与普通文字');
      expect(out, '粗体 与普通文字');
      expectNoPlaceholderLeak(out);
    });

    test('星号斜体', () {
      final String out = MarkdownParser.stripInline('*斜体* 结尾');
      expect(out, '斜体 结尾');
      expectNoPlaceholderLeak(out);
    });

    test('下划线斜体', () {
      final String out = MarkdownParser.stripInline('_斜体_ 结尾');
      expect(out, '斜体 结尾');
      expectNoPlaceholderLeak(out);
    });

    test('行内代码', () {
      final String out = MarkdownParser.stripInline('调用 `foo()` 即可');
      expect(out, '调用 foo() 即可');
      expectNoPlaceholderLeak(out);
    });

    test('链接与图片', () {
      expect(MarkdownParser.stripInline('[文字](https://a.com)'), '文字');
      expect(MarkdownParser.stripInline('![替代](https://a.com/x.png)'), '替代');
    });

    test('snake_case 不被当成斜体吃掉', () {
      for (final String text in <String>[
        'snake_case_name',
        'a_b_c_d',
        '变量 foo_bar 与 baz_qux',
        'http://a.com/b_c_d?x=y_z',
      ]) {
        final String out = MarkdownParser.stripInline(text);
        expect(out, text, reason: '"$text" 里的下划线是标识符，不是语法');
      }
    });

    test('混排时各语法都被剥掉且互不干扰', () {
      final String out = MarkdownParser.stripInline(
        '**粗体** 与 *斜体* 还有 snake_case 与 `code` 以及 [链接](https://a.com)',
      );
      expect(out, '粗体 与 斜体 还有 snake_case 与 code 以及 链接');
      expectNoPlaceholderLeak(out);
    });

    test('不成对的星号原样保留', () {
      final String out = MarkdownParser.stripInline('3 * 4 = 12');
      expect(out, '3 * 4 = 12');
    });
  });
}
