import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/services/source/cached_http.dart';

import '../support/fake_http_fetcher.dart';

void main() {
  late FakeHttpFetcher fetcher;
  late DateTime now;

  CachedHttp build({
    Duration ttl = const Duration(minutes: 10),
    int maxEntries = 8,
    int maxRetries = 2,
  }) {
    return CachedHttp(
      fetcher: fetcher,
      defaultTtl: ttl,
      maxEntries: maxEntries,
      maxRetries: maxRetries,
      baseDelay: const Duration(milliseconds: 1),
      clock: () => now,
    );
  }

  setUp(() {
    fetcher = FakeHttpFetcher();
    now = DateTime(2026, 1, 1);
  });

  test('TTL 内命中缓存，不重复发请求', () async {
    fetcher.route('/a', '<html>a</html>');
    final CachedHttp http = build();

    expect(await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'), '<html>a</html>');
    now = now.add(const Duration(minutes: 5));
    expect(await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'), '<html>a</html>');

    expect(fetcher.requests.length, 1);
  });

  test('TTL 过期后重新请求', () async {
    fetcher.route('/a', 'v1');
    final CachedHttp http = build(ttl: const Duration(minutes: 1));

    await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8');
    now = now.add(const Duration(minutes: 2));
    fetcher.route('/a', 'v2');
    expect(await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'), 'v2');

    expect(fetcher.requests.length, 2);
  });

  test('bypassCache 强制绕过缓存', () async {
    fetcher.route('/a', 'v1');
    final CachedHttp http = build();
    await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8');
    fetcher.route('/a', 'v2');
    expect(
      await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8', bypassCache: true),
      'v2',
    );
    expect(fetcher.requests.length, 2);
  });

  test('同一 URL 的并发请求被合并成一次', () async {
    fetcher.route('/a', 'body');
    final CachedHttp http = build();

    final List<String> results = await Future.wait<String>(<Future<String>>[
      http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'),
      http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'),
      http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'),
    ]);

    expect(results, <String>['body', 'body', 'body']);
    expect(fetcher.requests.length, 1);
    expect(http.inflightCount, 0);
  });

  test('瞬时网络故障会重试并最终成功', () async {
    fetcher.route('/a', 'body');
    fetcher.failTimesFor['/a'] = 1;
    final CachedHttp http = build();

    expect(await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'), 'body');
    expect(fetcher.requests.length, 2);
  });

  test('重试次数用尽后抛 network 错误', () async {
    fetcher.route('/a', 'body');
    fetcher.failTimesFor['/a'] = 99;
    final CachedHttp http = build(maxRetries: 2);

    await expectLater(
      http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'),
      throwsA(isA<SourceError>()
          .having((SourceError e) => e.kind, 'kind', SourceErrorKind.network)
          .having((SourceError e) => e.isRetryable, 'isRetryable', isTrue)),
    );
    expect(fetcher.requests.length, 3, reason: '首次 + 2 次重试');
  });

  test('5xx 会重试', () async {
    fetcher.route('/a', 'body');
    fetcher.statusFor['/a'] = 503;
    final CachedHttp http = build(maxRetries: 2);

    await expectLater(
      http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'),
      throwsA(isA<SourceError>().having((SourceError e) => e.kind, 'kind', SourceErrorKind.http)),
    );
    expect(fetcher.requests.length, 3);
  });

  test('404 不重试，直接判 notFound', () async {
    final CachedHttp http = build();
    await expectLater(
      http.getText(Uri.parse('https://ex.com/missing'), charset: 'utf-8'),
      throwsA(isA<SourceError>()
          .having((SourceError e) => e.kind, 'kind', SourceErrorKind.notFound)
          .having((SourceError e) => e.isRetryable, 'isRetryable', isFalse)),
    );
    expect(fetcher.requests.length, 1, reason: '4xx 重试是纯粹的浪费');
  });

  test('400 不重试', () async {
    fetcher.statusFor['/a'] = 400;
    final CachedHttp http = build();
    await expectLater(
      http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'),
      throwsA(isA<SourceError>().having((SourceError e) => e.kind, 'kind', SourceErrorKind.http)),
    );
    expect(fetcher.requests.length, 1);
  });

  test('按源声明的编码解码，忽略响应头里的错误 charset', () async {
    // 响应头故意声明 iso-8859-1，正文其实是 GBK——中文源的真实常态
    fetcher.bytesFor['/a'] = gbk.encode('星海拾遗');
    final CachedHttp http = build();

    final String text = await http.getText(Uri.parse('https://ex.com/a'), charset: 'gbk');
    expect(text, '星海拾遗');
  });

  test('声明 utf-8 但正文是 GBK 时会乱码（说明确实在按声明解码）', () async {
    fetcher.bytesFor['/a'] = gbk.encode('星海拾遗');
    final CachedHttp http = build();

    final String text = await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8');
    expect(text, isNot('星海拾遗'));
  });

  test('charset=auto 交给嗅探', () async {
    fetcher.bytesFor['/a'] = gbk.encode('星海拾遗');
    final CachedHttp http = build();
    expect(await http.getText(Uri.parse('https://ex.com/a'), charset: 'auto'), '星海拾遗');
  });

  test('缓存条目数超过上限时淘汰最旧的', () async {
    fetcher.route('/a', 'a');
    fetcher.route('/b', 'b');
    fetcher.route('/c', 'c');
    final CachedHttp http = build(maxEntries: 2);

    await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8');
    await http.getText(Uri.parse('https://ex.com/b'), charset: 'utf-8');
    await http.getText(Uri.parse('https://ex.com/c'), charset: 'utf-8');
    expect(http.entryCount, 2);

    // /a 已被淘汰 → 再取要重新发请求
    await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8');
    expect(fetcher.requests.length, 4);
  });

  test('invalidate 与 clear 能主动失效缓存', () async {
    fetcher.route('/a', 'a');
    final CachedHttp http = build();
    await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8');
    http.invalidate(Uri.parse('https://ex.com/a'));
    await http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8');
    expect(fetcher.requests.length, 2);

    http.clear();
    expect(http.entryCount, 0);
  });

  test('并发上限限制同时在飞的请求数', () async {
    for (int i = 0; i < 6; i++) {
      fetcher.route('/p$i', 'p$i');
    }
    final CachedHttp http = CachedHttp(
      fetcher: fetcher,
      permits: 2,
      baseDelay: const Duration(milliseconds: 1),
      clock: () => now,
    );

    await Future.wait<void>(<Future<void>>[
      for (int i = 0; i < 6; i++)
        http.getText(Uri.parse('https://ex.com/p$i'), charset: 'utf-8'),
    ]);
    expect(fetcher.requests.length, 6);
  });

  test('离线时抛可重试的 network 错误', () async {
    fetcher.offline = true;
    final CachedHttp http = build(maxRetries: 0);
    await expectLater(
      http.getText(Uri.parse('https://ex.com/a'), charset: 'utf-8'),
      throwsA(isA<SourceError>().having((SourceError e) => e.isRetryable, 'isRetryable', isTrue)),
    );
  });

  test('getDocument 返回可查询的 DOM', () async {
    fetcher.route('/a', '<html><body><p id="x">内容</p></body></html>');
    final CachedHttp http = build();
    final document = await http.getDocument(Uri.parse('https://ex.com/a'), charset: 'utf-8');
    expect(document.querySelector('#x')?.text, '内容');
  });

  test('GET 请求带上源声明的请求头', () async {
    fetcher.route('/a', 'a');
    final CachedHttp http = build();
    await http.getText(
      Uri.parse('https://ex.com/a'),
      charset: 'utf-8',
      headers: <String, String>{'Referer': 'https://ex.com/'},
    );
    expect(fetcher.requestHeaders.single['Referer'], 'https://ex.com/');
  });
}
