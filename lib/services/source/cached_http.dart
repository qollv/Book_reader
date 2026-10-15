import 'dart:async';
import 'dart:collection';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/services/source/http_fetcher.dart';
import 'package:novel_reader/services/source/text_decoder.dart';

/// 带缓存、请求合并、并发上限与精确重试的 HTTP 层。
///
/// 四件事各对应上游一个教训：
/// 1. **编码显式化**：先取 bytes 再按源声明解码（上游 `bodyAsText()` 被坑过）；
/// 2. **请求合并**：同一 URL 的并发请求只发一次（上游 `ProxyCoalescing`）；
/// 3. **TTL 缓存**：按条目数封顶 + 过期即弃（上游 `api/util/Cache`，
///    但它读写 key 不一致导致命中率为 0，这里 key 统一用规范化后的 URL）；
/// 4. **按异常类型重试**：只对网络错误与 5xx/429 退避重试，
///    4xx 立刻失败（上游是「非 2xx 就重试」，对 404 做了 3 次无用请求）。
class CachedHttp {
  CachedHttp({
    required HttpFetcher fetcher,
    this.defaultTtl = const Duration(minutes: 30),
    this.maxEntries = 64,
    this.permits = 4,
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 200),
    this.requestTimeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  })  : _fetcher = fetcher,
        _clock = clock ?? DateTime.now;

  final HttpFetcher _fetcher;
  final Duration defaultTtl;
  final int maxEntries;
  final int permits;
  final int maxRetries;
  final Duration baseDelay;
  final Duration requestTimeout;
  final DateTime Function() _clock;

  /// LRU：accessOrder 语义用「取出即重插」实现（Dart 的 LinkedHashMap 保持插入序）。
  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap<String, _CacheEntry>();
  final Map<String, Future<String>> _inflight = <String, Future<String>>{};
  final _Semaphore _semaphore = _Semaphore(0);
  bool _semaphoreReady = false;

  /// 统计口径：真实发出的 HTTP 请求数（缓存命中与合并都不计）。
  int requestCount = 0;

  int get entryCount => _cache.length;

  int get inflightCount => _inflight.length;

  Future<String> getText(
    Uri uri, {
    required String charset,
    Map<String, String> headers = const <String, String>{},
    Duration? ttl,
    bool bypassCache = false,
  }) {
    final String key = uri.toString();
    if (!bypassCache) {
      final _CacheEntry? hit = _cache.remove(key);
      if (hit != null && _clock().difference(hit.fetchedAt) < (ttl ?? defaultTtl)) {
        _cache[key] = hit; // 重新插到末尾 = 标记为最近使用
        return Future<String>.value(hit.text);
      }
      final Future<String>? running = _inflight[key];
      if (running != null) {
        return running; // 请求合并
      }
    }

    final Future<String> task = _start(uri, key, charset: charset, headers: headers);
    _inflight[key] = task;
    return task;
  }

  /// 跑一次请求并保证在**所有出口**（成功 / 失败 / 取消）都清掉在飞记录。
  ///
  /// 这里刻意用 async 函数 + finally，而不是给 `_run` 挂 `whenComplete`：
  /// 后者的两个写法都会咬人——`() => _inflight.remove(key)` 会把被移除的
  /// Future 当返回值，`whenComplete` 于是等它完成（自引用死锁）；
  /// 写成语句体虽然不死锁，但派生出的新 Future 无人监听，原始错误会在
  /// 它上面变成「未处理异常」，测试与线上都会看到来路不明的崩溃。
  /// async 函数返回的那个 Future 直接交给调用方，错误只有一条路径。
  Future<String> _start(
    Uri uri,
    String key, {
    required String charset,
    required Map<String, String> headers,
  }) async {
    try {
      return await _run(uri, charset: charset, headers: headers);
    } finally {
      // 清理在飞记录。返回值就是本次的 Future 本身，没有意义，显式丢弃。
      final Future<String>? discarded = _inflight.remove(key);
      discarded?.ignore();
    }
  }

  Future<dom.Document> getDocument(
    Uri uri, {
    required String charset,
    Map<String, String> headers = const <String, String>{},
    Duration? ttl,
    bool bypassCache = false,
  }) async {
    final String text = await getText(
      uri,
      charset: charset,
      headers: headers,
      ttl: ttl,
      bypassCache: bypassCache,
    );
    return html_parser.parse(text);
  }

  Future<String> _run(
    Uri uri, {
    required String charset,
    required Map<String, String> headers,
  }) async {
    await _acquire();
    try {
      HttpBytesResponse response;
      int attempt = 0;
      while (true) {
        try {
          requestCount++;
          response = await _fetcher.fetch(uri, headers: headers, timeout: requestTimeout);
        } on HttpFetchException catch (e) {
          if (!e.retryable || attempt >= maxRetries) {
            throw SourceError(SourceErrorKind.network, e.message, detail: '$uri');
          }
          await Future<void>.delayed(baseDelay * (1 << attempt));
          attempt++;
          continue;
        }

        if (response.statusCode == 404 || response.statusCode == 410) {
          throw SourceError(SourceErrorKind.notFound, '资源不存在 (${response.statusCode})', detail: '$uri');
        }
        final bool serverSide = response.statusCode >= 500 || response.statusCode == 429;
        if (response.statusCode >= 400) {
          if (!serverSide || attempt >= maxRetries) {
            throw SourceError(
              SourceErrorKind.http,
              'HTTP ${response.statusCode}',
              detail: '$uri',
            );
          }
          await Future<void>.delayed(baseDelay * (1 << attempt));
          attempt++;
          continue;
        }
        break;
      }

      final String text = decodeBytes(response.bytes, charset);
      _remember(uri.toString(), text);
      return text;
    } finally {
      _release();
    }
  }

  void _remember(String key, String text) {
    _cache.remove(key);
    _cache[key] = _CacheEntry(text, _clock());
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<void> _acquire() async {
    if (!_semaphoreReady) {
      _semaphore.max = permits;
      _semaphoreReady = true;
    }
    await _semaphore.acquire();
  }

  void _release() => _semaphore.release();

  /// 手动失效（如强制刷新详情页）。
  void invalidate(Uri uri) => _cache.remove(uri.toString());

  void clear() {
    _cache.clear();
    _inflight.clear();
  }
}

class _CacheEntry {
  const _CacheEntry(this.text, this.fetchedAt);

  final String text;
  final DateTime fetchedAt;
}

/// 极简信号量：限制单源并发，对应上游 `WebBookDataSource.permits`。
class _Semaphore {
  _Semaphore(this.max);

  int max;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_active < max) {
      _active++;
      return Future<void>.value();
    }
    final Completer<void> completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    if (_active > 0) {
      _active--;
    }
  }
}
