import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/services/import/lan_transfer_server.dart';

// TC-10：DEF-10 局域网服务健壮性（鉴权矩阵 / 端口占用退让 / 路径穿越防回归）。
void main() {
  late Directory tempDir;
  late LanTransferServer server;
  late HttpClient client;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lan_test_');
    await Directory('${tempDir.path}/books').create();
    await Directory('${tempDir.path}/inbox').create();
    server = LanTransferServer(
      booksRoot: '${tempDir.path}/books',
      inboxPath: '${tempDir.path}/inbox',
      syncStorePath: '${tempDir.path}/sync.json',
      onFileReceived: (_) {},
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<HttpClientResponse> get(String path, {String? token}) {
    return client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}$path'))
        .then((HttpClientRequest request) {
          if (token != null) {
            request.headers.set('x-token', token);
          }
          return request.close();
        });
  }

  test('端口被占用时自动退到系统分配端口', () async {
    final ServerSocket occupying = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int busyPort = occupying.port;
    await server.start(preferredPort: busyPort);
    expect(server.isRunning, isTrue);
    expect(server.port, isNot(busyPort));
    await occupying.close();
  });

  test('鉴权矩阵：无令牌/错令牌 403，正确令牌 200', () async {
    await server.start(preferredPort: 0);
    final HttpClientResponse noToken = await get('/books');
    expect(noToken.statusCode, 403);
    final HttpClientResponse badToken = await get('/books', token: 'WRONGXX');
    expect(badToken.statusCode, 403);
    final HttpClientResponse ok = await get('/books', token: server.token);
    expect(ok.statusCode, 200);
  });

  test('路径穿越三种编码均被拒（防回归）', () async {
    await server.start(preferredPort: 0);
    for (final String path in <String>[
      '/books/..%2fsecret.txt',
      '/books/%2e%2e%2fsecret.txt',
      '/books/..%5csecret.txt',
    ]) {
      final HttpClientResponse response = await get(path, token: server.token);
      expect(response.statusCode, 400, reason: path);
    }
  });

  test('上传落盘 inbox 且文件名被消毒（防回归）', () async {
    await server.start(preferredPort: 0);
    final HttpClientRequest request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/upload?name=..%2f..%2fpwned.txt'),
    );
    request.headers.set('x-token', server.token);
    request.write('book-content');
    final HttpClientResponse response = await request.close();
    expect(response.statusCode, 200);
    // 逃逸被拦：文件落在 inbox 内，而不是 tempDir 外
    expect(await File('${tempDir.path}/inbox/pwned.txt').exists(), isTrue);
    expect(await File('${tempDir.path}/pwned.txt').exists(), isFalse);
  });

  test('同步数据首拉取返回 404（对端无数据是正常场景）', () async {
    await server.start(preferredPort: 0);
    final HttpClientResponse response = await get('/sync', token: server.token);
    expect(response.statusCode, 404);
  });
}
