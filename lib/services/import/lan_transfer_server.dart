import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

/// 局域网传输服务端。
///
/// 配对方式：本机起 HTTP 服务，另一端扫码（含 IP/端口/令牌）后：
/// - GET  /books        拉取本机书库文件列表
/// - GET  /books/<name> 下载文件
/// - POST /upload       把文件推送过来（落盘 inbox，回调通知导入）
/// 所有数据接口都校验 X-Token 头，防止同网段其他设备随意读写。
class LanTransferServer {
  LanTransferServer({
    required String booksRoot,
    required String inboxPath,
    required void Function(String filePath) onFileReceived,
    required String syncStorePath,
  }) : _booksRoot = booksRoot,
       _inboxPath = inboxPath,
       _onFileReceived = onFileReceived,
       _syncStorePath = syncStorePath,
       _token = _randomToken();

  static const String _tokenHeader = 'x-token';

  /// 请求体上限：与 URL 导入一致（100MB）。
  static const int _maxBodyBytes = 100 * 1024 * 1024;

  final String _booksRoot;
  final String _inboxPath;
  final void Function(String filePath) _onFileReceived;
  final String _syncStorePath;
  final String _token;

  HttpServer? _server;
  int _port = 0;

  String get token => _token;
  bool get isRunning => _server != null;
  int get port => _port;

  /// 二维码内容：novelreader://pair?ip=&port=&token=
  String pairUri(String localIp) {
    return 'novelreader://pair?ip=$localIp&port=$_port&token=$_token';
  }

  Future<void> start({int preferredPort = 8620}) async {
    final Router router = Router()
      ..get('/info', _handleInfo)
      ..get('/books', _requireToken(_handleList))
      ..get('/books/<name>', _requireToken(_handleDownload))
      ..post('/upload', _requireToken(_handleUpload))
      ..get('/sync', _requireToken(_handleSyncDownload))
      ..post('/sync', _requireToken(_handleSyncUpload));

    try {
      _server = await serve(router.call, InternetAddress.anyIPv4, preferredPort, shared: false);
    } on SocketException {
      // 首选端口被占用：退到系统自动分配，而不是整个服务起不来
      _server = await serve(router.call, InternetAddress.anyIPv4, 0, shared: false);
    }
    _port = _server!.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }

  Response _handleInfo(Request request) {
    return Response.ok(
      jsonEncode(<String, Object?>{'app': 'novel-reader', 'version': 1}),
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  Handler _requireToken(Handler inner) {
    return (Request request) {
      if (request.headers[_tokenHeader] != _token) {
        return Response.forbidden('token mismatch');
      }
      return inner(request);
    };
  }

  Future<Response> _handleList(Request request) async {
    final Directory dir = Directory(_booksRoot);
    if (!await dir.exists()) {
      return _json(<Map<String, Object?>>[]);
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    await for (FileSystemEntity entity in dir.list(recursive: true)) {
      if (entity is File) {
        items.add(<String, Object?>{
          'name': p.relative(entity.path, from: _booksRoot),
          'size': await entity.length(),
        });
      }
    }
    return _json(items);
  }

  Future<Response> _handleDownload(Request request) async {
    final String? name = request.params['name'];
    if (name == null || name.contains('..')) {
      return Response.badRequest(body: 'invalid name');
    }
    final File file = File(p.join(_booksRoot, name));
    if (!await file.exists()) {
      return Response.notFound('file not found');
    }
    return Response.ok(file.openRead(), headers: <String, String>{
      'content-type': 'application/octet-stream',
      'content-disposition': 'attachment; filename="${Uri.encodeComponent(p.basename(name))}"',
    });
  }

  Future<Response> _handleUpload(Request request) async {
    final String? rawName = request.url.queryParameters['name'];
    if (rawName == null || rawName.trim().isEmpty) {
      return Response.badRequest(body: 'missing name');
    }
    // 只取文件名，杜绝 ../ 路径穿越
    final String safeName = p.basename(rawName.trim());
    if (safeName.isEmpty) {
      return Response.badRequest(body: 'invalid name');
    }
    final File target = File(p.join(_inboxPath, safeName));
    final List<int>? body = await _readBodyWithLimit(request);
    if (body == null) {
      return Response(413, body: 'body too large');
    }
    if (body.isEmpty) {
      return Response.badRequest(body: 'empty body');
    }
    // 临时文件 + rename 原子落盘，中断不会留下半个文件
    final File temp = File('${target.path}.tmp');
    await temp.writeAsBytes(body, flush: true);
    await temp.rename(target.path);
    _onFileReceived(target.path);
    return Response.ok(jsonEncode(<String, Object?>{'saved': safeName}),
        headers: <String, String>{'content-type': 'application/json'});
  }

  Response _json(Object data) {
    return Response.ok(
      jsonEncode(data),
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  // 同步数据存取：对方设备把进度/书签/笔记 JSON 推到这里，或从这里拉走。
  Future<Response> _handleSyncDownload(Request request) async {
    final File store = File(_syncStorePath);
    if (!await store.exists()) {
      return Response.notFound('no sync data');
    }
    return Response.ok(store.openRead(), headers: <String, String>{
      'content-type': 'application/json',
    });
  }

  Future<Response> _handleSyncUpload(Request request) async {
    final List<int>? body = await _readBodyWithLimit(request);
    if (body == null) {
      return Response(413, body: 'body too large');
    }
    if (body.isEmpty) {
      return Response.badRequest(body: 'empty body');
    }
    // 临时文件 + rename 原子落盘，避免中断损坏 sync.json
    final File temp = File('$_syncStorePath.tmp');
    await temp.writeAsBytes(body, flush: true);
    await temp.rename(_syncStorePath);
    return Response.ok(jsonEncode(<String, Object?>{'saved': true}),
        headers: <String, String>{'content-type': 'application/json'});
  }

  /// 读请求体并限制大小：先看 content-length，再按流累计上限（与 URL 导入一致 100MB）。
  /// 返回 null 表示超限。
  Future<List<int>?> _readBodyWithLimit(Request request) async {
    final Object? declared = request.headers['content-length'];
    if (declared != null) {
      final int? length = int.tryParse(declared.toString());
      if (length != null && length > _maxBodyBytes) {
        return null;
      }
    }
    final List<int> body = <int>[];
    await for (List<int> chunk in request.read()) {
      body.addAll(chunk);
      if (body.length > _maxBodyBytes) {
        return null;
      }
    }
    return body;
  }
}

String _randomToken() {
  final Random random = Random.secure();
  const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  // 8 位令牌：局域网明文传输，提高爆破成本
  return List<String>.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
}
