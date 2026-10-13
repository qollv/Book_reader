import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/text/text_normalizer.dart';

void main() {
  group('TextNormalizer.reflow', () {
    test('merges hard-wrapped lines into one paragraph', () {
      const String raw = '第一行没写完\n第二行继续\n\n新的一段。';
      final List<String> result = TextNormalizer.reflow(raw);
      expect(result, hasLength(2));
      expect(result[0], '第一行没写完第二行继续');
      expect(result[1], '新的一段。');
    });

    test('keeps paragraph boundary when line ends with sentence punctuation', () {
      const String raw = '这是第一句。\n这是第二句。';
      final List<String> result = TextNormalizer.reflow(raw);
      expect(result, hasLength(2));
    });

    test('drops blank lines and trims spaces', () {
      const String raw = '\n  你好  \n\n  世界  \n';
      final List<String> result = TextNormalizer.reflow(raw);
      expect(result, <String>['你好', '世界']);
    });

    test('empty input yields empty list', () {
      expect(TextNormalizer.reflow(''), isEmpty);
      expect(TextNormalizer.reflow('\n\n\n'), isEmpty);
    });
  });
}
