import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/services/import/url_importer.dart';

import 'test_support.dart';

/// URL 导入功能测试（FT-URL 系列）。
/// 校验类用例不走网络；端到端用例用本地 HttpServer 提供直链。
void main() {
  group('FT-URL 导入', () {
    late TestHarness harness;
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      harness = await createHarness();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
      await harness.dispose();
    });

    UrlImporter importer() => UrlImporter(harness.bookRepository);

    test('FT-URL-01 合法 txt 直链端到端导入成功', () async {
      final List<int> body = utf8.encode('书名直链测试\n\n第一章 开始\n\n从前有座山。\n');
      server.listen((HttpRequest request) async {
        // HEAD 预检不得携带 body，否则 dart:io 返回 400
        if (request.method == 'HEAD') {
          request.response.headers.contentLength = body.length;
          await request.response.close();
          return;
        }
        request.response.headers.contentLength = body.length;
        request.response.add(body);
        await request.response.close();
      });

      final Book book = await importer().importFromUrl('$baseUrl/book.txt');
      expect(book.title, '书名直链测试');
      expect(book.chapterCount, 1);
    });

    test('FT-URL-02 HEAD 预检声明超过 100MB 直接拒绝且不落库', () async {
      server.listen((HttpRequest request) async {
        if (request.method == 'HEAD') {
          request.response.headers.contentLength = 101 * 1024 * 1024;
          await request.response.close();
          return;
        }
        fail('预检超限后不应再发起 GET 下载');
      });

      await expectLater(
        importer().importFromUrl('$baseUrl/huge.txt'),
        throwsA(isA<ImportException>()
            .having((ImportException e) => e.message, 'message', contains('100MB'))),
      );
      final List<Map<String, Object?>> rows =
          await harness.database.query('books');
      expect(rows, isEmpty);
    });

    test('FT-URL-03 非 http/https 协议拒绝', () async {
      await expectLater(
        importer().importFromUrl('ftp://example.com/book.txt'),
        throwsA(isA<ImportException>()
            .having((ImportException e) => e.message, 'message', contains('http/https'))),
      );
      await expectLater(
        importer().importFromUrl('file:///etc/passwd.txt'),
        throwsA(isA<ImportException>()
            .having((ImportException e) => e.message, 'message', contains('http/https'))),
      );
    });

    test('FT-URL-04 畸形链接拒绝', () async {
      for (String bad in <String>['', '   ', 'not-a-url', 'http://', '://missing']) {
        await expectLater(
          importer().importFromUrl(bad),
          throwsA(isA<ImportException>()),
          reason: '链接 [$bad] 应被拒绝',
        );
      }
    });

    test('FT-URL-05 不支持的扩展名拒绝（白名单外）', () async {
      for (String ext in <String>['pdf', 'epub', 'exe', 'zip', '']) {
        await expectLater(
          importer().importFromUrl('$baseUrl/book.$ext'),
          throwsA(isA<ImportException>()
              .having((ImportException e) => e.message, 'message', contains('txt / md / docx'))),
          reason: '扩展名 [$ext] 不在白名单',
        );
      }
    });

    test('FT-URL-06 服务端 404 时异常向上传播（由控制器层兜底为友好提示）', () async {
      server.listen((HttpRequest request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });

      // importer 层不吞网络异常，DioException 原样冒泡；
      // BookshelfController.importFromUrl 的 catch 会把它转成 SnackBar 文案
      await expectLater(
        importer().importFromUrl('$baseUrl/missing.txt'),
        throwsA(isA<DioException>().having(
            (DioException e) => e.response?.statusCode, 'statusCode', 404)),
      );
    });

    test('FT-URL-07 大写扩展名与查询串参数正常放行', () async {
      final List<int> body = utf8.encode('直链大小写\n\n正文第一段。\n');
      server.listen((HttpRequest request) async {
        if (request.method == 'HEAD') {
          request.response.headers.contentLength = body.length;
          await request.response.close();
          return;
        }
        request.response.headers.contentLength = body.length;
        request.response.add(body);
        await request.response.close();
      });

      final Book book =
          await importer().importFromUrl('$baseUrl/BOOK.TXT?from=share&token=x');
      expect(book.title, '直链大小写');
    });
  });
}
