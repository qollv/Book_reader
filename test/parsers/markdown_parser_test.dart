import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/markdown_parser.dart';

// TC-02：DEF-03 行内语法剥离。Dart 的 replaceAll(RegExp, String) 不解析 $n，
// 曾把 **粗体** 替换成字面量 $1，必须用 replaceAllMapped。
void main() {
  group('stripInline', () {
    test('粗体/斜体/行内代码/链接/图片取分组内容', () {
      expect(MarkdownParser.stripInline('**粗体**'), '粗体');
      expect(MarkdownParser.stripInline('*斜体*'), '斜体');
      expect(MarkdownParser.stripInline('`code`'), 'code');
      expect(MarkdownParser.stripInline('[文字](http://a.com)'), '文字');
      expect(MarkdownParser.stripInline('![图](http://a.com/x.png)'), '图');
      expect(MarkdownParser.stripInline('**粗体** 与 *斜体*'), '粗体 与 斜体');
    });

    test('snake_case 与 URL 下划线不被误吞', () {
      expect(MarkdownParser.stripInline('snake_case_name'), 'snake_case_name');
      expect(MarkdownParser.stripInline('变量 foo_bar 与 baz_qux'), '变量 foo_bar 与 baz_qux');
      expect(MarkdownParser.stripInline('http://a.com/b_c_d?x=y_z'), 'http://a.com/b_c_d?x=y_z');
    });

    test('正文中不得出现字面量反向引用', () {
      const String input = '**a** *b* `c` [d](e) ![f](g)';
      final String output = MarkdownParser.stripInline(input);
      expect(output.contains('\$1'), isFalse);
      expect(output, 'a b c d f');
    });
  });
}
