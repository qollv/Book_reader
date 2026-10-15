import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/markdown_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';

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
  group('md 书名标题前缀', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('md_title_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<String> titleOf(String content, {String name = 't.md'}) async {
      final File file = File('${tempDir.path}/$name');
      await file.writeAsString(content);
      return (await MarkdownParser().parseFile(file.path)).title;
    }

    test('一级标题书名剥离 # 前缀', () async {
      expect(await titleOf('# 测试书名\n\n## 第一章\n\n正文。'), '测试书名');
    });

    test('多级标题书名同样剥离', () async {
      expect(await titleOf('## 二级书名\n\n正文。'), '二级书名');
      expect(await titleOf('### 三级书名\n\n正文。'), '三级书名');
    });

    test('无标题标记的首行书名保持原样', () async {
      expect(await titleOf('普通书名\n\n正文。'), '普通书名');
    });

    test('书名行从正文中移除，不在第一章重复出现', () async {
      final File file = File('${tempDir.path}/dup.md');
      await file.writeAsString('# 书名行\n\n## 第一章\n\n正文。');
      final ParsedBook book = await MarkdownParser().parseFile(file.path);
      for (final ParsedChapter chapter in book.chapters) {
        for (final block in chapter.blocks) {
          expect(block.text, isNot('书名行'));
        }
      }
    });
  });
}

// TC-22：DEF-01 md 书名剥离标题前缀。书架/目录不得显示「# 」前缀。