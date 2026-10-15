import 'dart:convert';
import 'dart:io';

import 'package:novel_reader/services/source/http_fetcher.dart';

/// 内存 HTTP 桩：把 URI 映射到本地 fixture 文件或程序化响应。
///
/// 有了它，缓存/重试/编码/规则引擎全部可以离线测——不必起服务器，
/// 也不必依赖任何真实站点（真实站点的选择器随时会变，测它等于测网站）。
class FakeHttpFetcher implements HttpFetcher {
  FakeHttpFetcher();

  /// 路径（含 query）→ 响应体。
  final Map<String, String> routes = <String, String>{};

  /// 记录每一次真实发起的请求，用于断言缓存/合并/重试行为。
  final List<Uri> requests = <Uri>[];

  /// 命中的请求头，键为请求顺序。
  final List<Map<String, String>> requestHeaders = <Map<String, String>>[];

  /// 指定路径在若干次请求后失败：路径 → 剩余失败次数。
  final Map<String, int> failTimesFor = <String, int>{};

  /// 指定路径固定返回的状态码。
  final Map<String, int> statusFor = <String, int>{};

  /// 指定路径的响应字节（用于编码测试）。
  final Map<String, List<int>> bytesFor = <String, List<int>>{};

  /// 全部置为网络错误。
  bool offline = false;

  /// 响应头，可用来验证「不依赖响应头声明 charset」。
  Map<String, List<String>> headersFor(String path) => <String, List<String>>{
        'content-type': <String>['text/html; charset=iso-8859-1'],
      };

  void route(String path, String body) => routes[path] = body;

  /// 从磁盘装载 fixture（`test/fixtures/*.html`）。
  Future<void> routeFile(String path, String filePath) async {
    routes[path] = await File(filePath).readAsString();
  }

  /// 从磁盘装载 fixture，并以**指定编码的字节**返回（测 GBK 等场景）。
  Future<void> routeFileBytes(String path, String filePath) async {
    bytesFor[path] = await File(filePath).readAsBytes();
  }

  @override
  Future<HttpBytesResponse> fetch(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  }) async {
    final String path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    requests.add(uri);
    requestHeaders.add(Map<String, String>.from(headers));

    if (offline) {
      throw const HttpFetchException('网络不可达: fake offline');
    }

    final int? status = statusFor[path] ?? statusFor[uri.path];
    if (status != null && status >= 400) {
      return HttpBytesResponse(statusCode: status, bytes: utf8.encode('error'));
    }

    final int remaining = failTimesFor[path] ?? failTimesFor[uri.path] ?? 0;
    if (remaining > 0) {
      failTimesFor[path] = remaining - 1;
      if (path != uri.path) {
        failTimesFor[uri.path] = remaining - 1;
      }
      throw const HttpFetchException('模拟瞬时网络故障');
    }

    final List<int>? rawBytes = bytesFor[path] ?? bytesFor[uri.path];
    if (rawBytes != null) {
      return HttpBytesResponse(
        statusCode: 200,
        bytes: rawBytes,
        headers: headersFor(path),
      );
    }

    final String? body = routes[path] ?? routes[uri.path];
    if (body == null) {
      return const HttpBytesResponse(statusCode: 404, bytes: <int>[]);
    }
    return HttpBytesResponse(
      statusCode: 200,
      bytes: utf8.encode(body),
      // 故意声明一个错误的 charset：正确的实现必须忽略它，用源声明的编码解码
      headers: headersFor(path),
    );
  }
}
