// 复现用测试 6：局域网服务端行为（分析工具生成）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/services/import/lan_transfer_server.dart';
import 'package:novel_reader/services/sync/sync_transports.dart';

Future<(int, String)> request(
  int port,
  String method,
  String path, {
  Map<String, String> headers = const <String, String>{},
  String? body,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest req =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    headers.forEach(req.headers.set);
    if (body != null) {
      req.write(body);
    }
    final HttpClientResponse res = await req.close();
    final String text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.length > 120 ? '${text.substring(0, 120)}...' : text);
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('R17 局域网服务端：鉴权/路径/端口占用/404 语义', () async {
    final Directory root = await Directory.systemTemp.createTemp('repro_lan_');
    final Directory books = Directory('${root.path}${Platform.pathSeparator}books')..createSync();
    final Directory inbox = Directory('${root.path}${Platform.pathSeparator}inbox')..createSync();
    await File('${books.path}${Platform.pathSeparator}a.txt').writeAsString('book-content');
    await File('${root.path}${Platform.pathSeparator}secret_outside.txt').writeAsString('SECRET');

    final List<String> received = <String>[];
    final LanTransferServer server = LanTransferServer(
      booksRoot: books.path,
      inboxPath: inbox.path,
      syncStorePath: '${root.path}${Platform.pathSeparator}sync.json',
      onFileReceived: received.add,
    );
    await server.start(preferredPort: 0);
    final int port = server.port;
    print('R17 port=$port token=${server.token} pair=${server.pairUri('192.168.1.5')}');

    print('R17 1) 无令牌 GET /books -> ${await request(port, 'GET', '/books')}');
    print('R17 2) 有令牌 GET /books -> ${await request(port, 'GET', '/books', headers: <String, String>{'x-token': server.token})}');
    print('R17 3) GET /info(免鉴权) -> ${await request(port, 'GET', '/info')}');
    print('R17 4) GET /books/a.txt -> ${await request(port, 'GET', '/books/a.txt', headers: <String, String>{'x-token': server.token})}');
    print('R17 5) GET /books/..%2fsecret_outside.txt -> '
        '${await request(port, 'GET', '/books/..%2fsecret_outside.txt', headers: <String, String>{'x-token': server.token})}');
    print('R17 6) GET /books/%2e%2e%2fsecret_outside.txt -> '
        '${await request(port, 'GET', '/books/%2e%2e%2fsecret_outside.txt', headers: <String, String>{'x-token': server.token})}');
    print('R17 7) GET /books/..\\secret_outside.txt -> '
        '${await request(port, 'GET', '/books/..%5Csecret_outside.txt', headers: <String, String>{'x-token': server.token})}');
    print('R17 8) POST /upload?name=..%2f..%2fpwned.txt -> '
        '${await request(port, 'POST', '/upload?name=..%2f..%2fpwned.txt', headers: <String, String>{'x-token': server.token}, body: 'x')}');

    final List<String> created = <String>[];
    await for (final FileSystemEntity entity in root.list(recursive: true)) {
      created.add(entity.path.replaceFirst(root.path, ''));
    }
    print('R17 files under root=$created');
    print('R17 onFileReceived=$received');
    print('R17 secret content still=${File('${root.path}${Platform.pathSeparator}secret_outside.txt').readAsStringSync()}');

    // Dio 对 404 的默认行为 / LanSyncTransport.download 的 404 分支
    try {
      final dynamic payload =
          await LanSyncTransport(peerBaseUrl: 'http://127.0.0.1:$port', token: server.token).download();
      print('R17 9) LanSyncTransport.download(404 无同步文件) -> $payload');
    } catch (error) {
      print('R17 9) LanSyncTransport.download(404 无同步文件) THREW: ${error.runtimeType}: $error');
    }

    // 端口占用：同一端口再起一个服务
    final LanTransferServer second = LanTransferServer(
      booksRoot: books.path,
      inboxPath: inbox.path,
      syncStorePath: '${root.path}${Platform.pathSeparator}sync2.json',
      onFileReceived: (_) {},
    );
    try {
      await second.start(preferredPort: port);
      print('R17 10) 同端口第二次 start 成功，实际端口=${second.port}（说明端口被占用时未抛错）');
      await second.stop();
    } catch (error) {
      print('R17 10) 同端口第二次 start THREW: ${error.runtimeType}: $error');
    }

    await server.stop();
  });
}
