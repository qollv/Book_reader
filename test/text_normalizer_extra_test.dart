import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/text/text_normalizer.dart';

// TC-05：DEF-13 续行合并。英文句末标点曾不被识别，跨行英文被粘成一个词。
void main() {
  group('TextNormalizer.reflow 增强', () {
    test('英文跨行拼接补空格', () {
      expect(TextNormalizer.reflow('hello\nworld'), <String>['hello world']);
    });

    test('CJK 相邻不补空格', () {
      expect(TextNormalizer.reflow('第一行\n第二行'), <String>['第一行第二行']);
    });

    test('英文句末标点分段', () {
      expect(TextNormalizer.reflow('line one.\nline two.'), hasLength(2));
    });

    test('中英混排补空格', () {
      expect(TextNormalizer.reflow('使用 Flutter\n框架开发'), <String>['使用 Flutter 框架开发']);
    });

    test('CRLF 换行正常', () {
      expect(TextNormalizer.reflow('第一行\r\n第二行'), <String>['第一行第二行']);
    });
  });
}
