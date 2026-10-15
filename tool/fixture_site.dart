// 本地 fixture 站点：用来演示与端到端验证声明式数据源。
//
// 启动：
//   dart run tool/fixture_site.dart            # 默认 http://127.0.0.1:8765
//   dart run tool/fixture_site.dart 9000       # 指定端口
//
// 然后在应用里「探索 → 数据源管理 → 安装内置示例源」，即可浏览/搜索/导入。
//
// 为什么要有一个 fixture 站点：
// 真实小说站点的选择器随时会变，拿它做开发与测试等于把别人的线上改动
// 引进自己的测试。fixture 站点是稳定的、可离线跑的、能覆盖边界
// （缺 id 的条目、空白段、分卷、相对地址封面）的对照组。
import 'dart:convert';
import 'dart:io';

/// 章节 id → 标题，与 fixtures/book.html 的目录保持一致。
const Map<String, String> fixtureChapters = <String, String>{
  '1001': '第一章 锈迹',
  '1002': '第二章 回声',
  '1003': '第三章 出港',
};

/// 可嵌入测试进程的 fixture 站点。
class FixtureSite {
  FixtureSite._(this._server, this.port, this._fixturesDir);

  final HttpServer _server;
  final int port;
  final String _fixturesDir;

  String get baseUrl => 'http://127.0.0.1:$port';

  /// 绑定到 127.0.0.1；[port] 传 0 表示由系统分配（测试用）。
  static Future<FixtureSite> start({
    int port = 8765,
    String fixturesDir = 'test/fixtures',
  }) async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final FixtureSite site = FixtureSite._(server, server.port, fixturesDir);
    site._serve();
    return site;
  }

  Future<void> stop() => _server.close(force: true);

  void _serve() {
    _server.listen((HttpRequest request) async {
      final String path = request.uri.path;
      try {
        if (path == '/rank' || path == '/latest' || path == '/') {
          await _sendFile(request, 'rank.html');
        } else if (path == '/search') {
          await _sendFile(request, 'search.html');
        } else if (path.startsWith('/book/')) {
          await _sendFile(request, 'book.html');
        } else if (path.startsWith('/read/')) {
          await _sendGeneratedChapter(request, path.substring('/read/'.length));
        } else if (path.startsWith('/cover/')) {
          // 1x1 透明 PNG：封面抓取在演示里只需要一个能返回 200 的地址
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType('image', 'png');
          request.response.add(<int>[
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
            0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
            0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
          ]);
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      } on Object catch (e) {
        stderr.writeln('fixture 站点处理 $path 失败: $e');
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } on Object {
          // 连接已经断了，忽略
        }
      }
    });
  }

  Future<void> _sendFile(HttpRequest request, String name) async {
    final File file = File('$_fixturesDir/$name');
    if (!await file.exists()) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType('text', 'html', charset: 'utf-8');
    request.response.add(await file.readAsBytes());
    await request.response.close();
  }

  /// 章节正文按 id 程序化生成：目录里有几章就能抓几章，不必手写 fixture。
  /// 不在目录里的 id 一律 404——真实站点不会给不存在的章节编内容，
  /// 这里放宽会让「404 处理」这条路径永远测不到。
  Future<void> _sendGeneratedChapter(HttpRequest request, String chapterId) async {
    final String? title = fixtureChapters[chapterId];
    if (title == null) {
      request.response
        ..statusCode = 404
        ..headers.contentType = ContentType('text', 'html', charset: 'utf-8');
      request.response.add(utf8.encode('<html><body>没有这一章</body></html>'));
      await request.response.close();
      return;
    }
    final List<String> ids = fixtureChapters.keys.toList(growable: false);
    final int index = ids.indexOf(chapterId);
    final String prevId = index > 0 ? ids[index - 1] : '1000';
    final String nextId = index < ids.length - 1 ? ids[index + 1] : '';

    final StringBuffer html = StringBuffer()
      ..writeln('<html><head><meta charset="utf-8"><title>$title</title></head><body>')
      ..writeln('<h1 id="title">$title</h1>')
      ..writeln('<div id="content">')
      ..writeln('<p>　　$title 的正文第一段，用来验证段落解析与首行缩进处理。</p>')
      ..writeln('<p>　　第二段里带一个 <b>加粗</b> 与一个 <a href="/read/$chapterId">自链接</a>，'
          '用于验证内联标签被正确降级为纯文本。</p>')
      ..writeln('<p>&nbsp;</p>')
      ..writeln('<p>　　第三段在空白段之后，用来验证空白段被丢弃。</p>')
      ..writeln('</div>')
      ..writeln('<div class="pager">')
      ..writeln('<a id="prev" href="/read/$prevId">上一章</a>');
    if (nextId.isNotEmpty) {
      html.writeln('<a id="next" href="/read/$nextId">下一章</a>');
    } else {
      html.writeln('<a id="next" href="#">下一章</a>');
    }
    html
      ..writeln('</div></body></html>');

    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType('text', 'html', charset: 'utf-8');
    request.response.add(utf8.encode(html.toString()));
    await request.response.close();
  }
}

Future<void> main(List<String> args) async {
  final int port = args.isEmpty ? 8765 : int.parse(args.first);
  final FixtureSite site = await FixtureSite.start(port: port);
  stdout.writeln('fixture 站点已启动: ${site.baseUrl}');
  stdout.writeln('  探索页  ${site.baseUrl}/rank');
  stdout.writeln('  详情页  ${site.baseUrl}/book/101');
  stdout.writeln('  正文页  ${site.baseUrl}/read/1001');
  stdout.writeln('在应用里安装「内置示例源」即可使用（baseUrl 已指向该地址）。Ctrl+C 退出。');
}
