import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 一次 HTTP 响应的原始形态：状态码 + 字节 + 响应头。
///
/// 刻意在**字节**这一层收口：编码在 [CachedHttp] 里按源声明处理，
/// 传输层不关心业务字符集。
class HttpBytesResponse {
  const HttpBytesResponse({
    required this.statusCode,
    required this.bytes,
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final List<int> bytes;
  final Map<String, List<String>> headers;
}

/// HTTP 传输抽象。生产用 dio/socket 实现，测试用内存桩，
/// 于是缓存/重试/编码/规则引擎全部可以离线测。
abstract class HttpFetcher {
  /// 发起一次请求。失败时抛 [HttpFetchException]。
  Future<HttpBytesResponse> fetch(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  });
}

/// 传输层异常，携带「是否值得重试」的判断依据。
class HttpFetchException implements Exception {
  const HttpFetchException(this.message, {this.retryable = true, this.cause});

  final String message;
  final bool retryable;
  final Object? cause;

  @override
  String toString() => 'HttpFetchException: $message';
}

/// 基于 dart:io 的 [HttpFetcher]：不引入 dio，保持零 native 依赖。
///
/// dio 的 `ResponseType.bytes` 同样可用，但阅读器只需要 GET，
/// 直接用它少一个抽象层；要换成 dio 只需再写一个 HttpFetcher 实现。
class IoHttpFetcher implements HttpFetcher {
  IoHttpFetcher({HttpClient? client, this.userAgent = defaultUserAgent})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  final String userAgent;

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';

  @override
  Future<HttpBytesResponse> fetch(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  }) async {
    final HttpClientRequest request = await _client
        .getUrl(uri)
        .timeout(timeout ?? const Duration(seconds: 15));
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(HttpHeaders.userAgentHeader, headers['User-Agent'] ?? userAgent);
    request.headers.set(HttpHeaders.acceptHeader,
        headers['Accept'] ?? 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate');
    for (final MapEntry<String, String> e in headers.entries) {
      if (e.key.toLowerCase() == 'host' || e.key.toLowerCase() == 'content-length') {
        continue; // 交由 HttpClient 管理，避免踩到非法头
      }
      request.headers.set(e.key, e.value);
    }

    final HttpClientResponse response =
        await request.close().timeout(timeout ?? const Duration(seconds: 20));
    final List<int> bytes = await _readAll(response);
    return HttpBytesResponse(
      statusCode: response.statusCode,
      bytes: bytes,
      headers: <String, List<String>>{
        for (final String name in <String>['content-type', 'content-encoding', 'location'])
          if (response.headers.value(name) != null) name: <String>[response.headers.value(name)!],
      },
    );
  }

  Future<List<int>> _readAll(HttpClientResponse response) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    // dart:io 的 HttpClient 默认自动解压 gzip/deflate，无需手动处理
    await for (final List<int> chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void close() => _client.close(force: true);
}

/// 把底层异常翻译成「是否重试」的语义。
HttpFetchException translateIoError(Object error) {
  if (error is TimeoutException) {
    return HttpFetchException('请求超时', cause: error);
  }
  if (error is SocketException) {
    return HttpFetchException('网络不可达: ${error.osError?.message ?? error.message}', cause: error);
  }
  if (error is HandshakeException) {
    return const HttpFetchException('TLS 握手失败', retryable: false);
  }
  if (error is HttpException) {
    return HttpFetchException('HTTP 传输失败: ${error.message}', cause: error);
  }
  return HttpFetchException('未知传输错误: $error', cause: error);
}
