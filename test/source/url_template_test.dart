import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/core/source/url_template.dart';

void main() {
  group('UrlTemplate', () {
    test('替换固定变量与调用变量', () {
      const UrlTemplate template = UrlTemplate('/book/{id}?page={page}');
      expect(
        template.expand(<String, String>{'id': '101', 'page': '2'}).toString(),
        '/book/101?page=2',
      );
    });

    test('固定变量参与替换', () {
      const UrlTemplate template = UrlTemplate('{base}/book/{id}',
          vars: <String, String>{'base': 'https://ex.com'});
      expect(template.expand(<String, String>{'id': '101'}).toString(), 'https://ex.com/book/101');
    });

    test('未提供的变量替换为空串，并被记录下来', () {
      const UrlTemplate template = UrlTemplate('/book/{id}/v{missing}');
      final ({String text, List<String> unresolved}) raw =
          template.expandRaw(<String, String>{'id': '101'});
      expect(raw.text, '/book/101/v');
      expect(raw.unresolved, <String>['missing']);
    });

    test('调用方变量覆盖固定变量', () {
      const UrlTemplate template =
          UrlTemplate('{base}/x', vars: <String, String>{'base': 'https://a'});
      expect(
        template.expand(<String, String>{'base': 'https://b'}).toString(),
        'https://b/x',
      );
    });

    test('绝对路径拼到 base 上', () {
      const UrlTemplate template = UrlTemplate('/search?q=x');
      expect(
        template.expand(const <String, String>{}, base: Uri.parse('https://ex.com/a/b'))
            .toString(),
        'https://ex.com/search?q=x',
      );
    });

    test('相对路径按 base 目录解析', () {
      const UrlTemplate template = UrlTemplate('next.html');
      expect(
        template.expand(const <String, String>{}, base: Uri.parse('https://ex.com/read/1'))
            .toString(),
        'https://ex.com/read/next.html',
      );
    });

    test('模板里带完整 URL 时忽略 base', () {
      const UrlTemplate template = UrlTemplate('https://other.com/x');
      expect(
        template.expand(const <String, String>{}, base: Uri.parse('https://ex.com/')).toString(),
        'https://other.com/x',
      );
    });

    test('unresolvedIn 便于排查缺失变量', () {
      const UrlTemplate template = UrlTemplate('/a/{one}/{two}');
      expect(
        template.unresolvedIn(<String, String>{'one': '1'}),
        <String>['two'],
      );
    });
  });
}
