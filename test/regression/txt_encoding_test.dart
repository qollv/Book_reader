import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/core/parsers/book_file_guard.dart';
import 'package:novel_reader/core/parsers/markdown_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/parsers/txt_parser.dart';
import 'package:novel_reader/core/text/byte_text_decoder.dart';

/// 编码与导入边界回归测试。
///
/// 背景：原实现是 `File(path).readAsString(encoding: utf8)`，写死 UTF-8。
/// 中文小说的 txt 大量是 GBK/ANSI，导入直接抛
/// `FileSystemException: Failed to decode data using encoding 'utf-8'`——
/// 用户看到一个和「编码」毫无关系的报错，而且完全无从处理。
/// 误选一个 pdf 也是同一个报错。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('encoding_regression_');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  Future<String> write(String name, List<int> bytes) async {
    final String path = '${dir.path}${Platform.pathSeparator}$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  group('解码器', () {
    test('合法 UTF-8 走 utf-8', () {
      final DecodedText decoded = decodeBookFileBytes(Uint8List.fromList(utf8.encode('中文正文')));
      expect(decoded.text, '中文正文');
      expect(decoded.encoding, 'utf-8');
    });

    test('UTF-8 BOM 被剥掉', () {
      final DecodedText decoded =
          decodeBookFileBytes(Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('书名')]));
      expect(decoded.text, '书名');
      expect(decoded.encoding, 'utf-8-bom');
      expect(decoded.text.codeUnits.contains(0xFEFF), isFalse);
    });

    test('UTF-16LE BOM 正确解码', () {
      final List<int> bytes = <int>[0xFF, 0xFE];
      for (final int unit in '书名'.codeUnits) {
        bytes.addAll(<int>[unit & 0xFF, unit >> 8]);
      }
      final DecodedText decoded = decodeBookFileBytes(Uint8List.fromList(bytes));
      expect(decoded.text, '书名');
      expect(decoded.encoding, 'utf-16le');
    });

    test('GBK 字节回退到 gbk 而不是抛异常', () {
      final DecodedText decoded = decodeBookFileBytes(Uint8List.fromList(gbk.encode('第一章 起风了')));
      expect(decoded.text, '第一章 起风了');
      expect(decoded.encoding, 'gbk');
    });

    test('GBK 里能解出的字节不会误导 UTF-8 判定（先严格 UTF-8）', () {
      // 一段正常 UTF-8 中文，绝不能被当成 GBK 解出乱码
      final DecodedText decoded = decodeBookFileBytes(Uint8List.fromList(utf8.encode('变量 foo_bar')));
      expect(decoded.text, '变量 foo_bar');
    });

    test('NUL 占比高的内容被判为二进制', () {
      final List<int> pdfish = <int>[0x25, 0x50, 0x44, 0x46, ...List<int>.filled(200, 0)];
      expect(looksBinary(Uint8List.fromList(pdfish)), isTrue);
      expect(
        () => decodeBookFileBytes(Uint8List.fromList(pdfish)),
        throwsA(isA<TextDecodeException>()
            .having((TextDecodeException e) => e.message, 'message', contains('不是文本'))),
      );
    });

    test('空文件给出可读错误', () {
      expect(
        () => decodeBookFileBytes(Uint8List(0)),
        throwsA(isA<TextDecodeException>()),
      );
    });

    test('按声明编码解码：不猜、不回退', () {
      // 站点声明 utf-8，就用 utf-8；解不出来是乱码，不该偷偷换成 gbk
      final List<int> gbkBytes = gbk.encode('星海拾遗');
      expect(decodeWithCharset(gbkBytes, 'gbk'), '星海拾遗');
      expect(decodeWithCharset(gbkBytes, 'utf-8'), isNot('星海拾遗'));
    });
  });

  group('txt 解析', () {
    test('GBK 编码的 txt 能正常导入（原来直接抛异常）', () async {
      // 手写字节，不依赖 charset 包的编码方向，确保测的是解码
      final List<int> gbkBytes = <int>[
        0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2, 0x20, 0xC6, 0xF0, 0xB7, 0xE7, 0xC1, 0xCB, 0x0A,
        0xD5, 0xFD, 0xCE, 0xC4, 0xD2, 0xBB, 0xA1, 0xA3,
      ];
      final ParsedBook book = await TxtParser().parseFile(await write('gbk.txt', gbkBytes));

      expect(book.title, '第一章 起风了');
      expect(book.chapters.single.blocks.single.text, '正文一。');
    });

    test('带 BOM 的 UTF-8 txt 不会把 BOM 带进书名', () async {
      final ParsedBook book = await TxtParser().parseFile(
        await write('bom.txt', <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('书名\n正文。')]),
      );

      expect(book.title, '书名');
      expect(book.title.codeUnits.contains(0xFEFF), isFalse);
    });

    test('markdown 解析器共享同一套解码（GBK 的 md 也能读）', () async {
      final ParsedBook book = await MarkdownParser()
          .parseFile(await write('gbk.md', gbk.encode('# 书名\n\n## 第一章\n\n正文。')));

      // 书名不该带 # 前缀，也不该在正文里重复出现
      expect(book.title, '书名');
      expect(book.chapters.map((ParsedChapter c) => c.title).toList(), contains('第一章'));
      for (final ParsedChapter chapter in book.chapters) {
        for (final ParagraphBlock block in chapter.blocks) {
          expect(block.text.contains('#'), isFalse, reason: '正文里不该残留 # 标记');
        }
      }
    });

    test('markdown 以 # 标题开头时书名剥掉井号', () async {
      final ParsedBook book =
          await MarkdownParser().parseFile(await write('t.md', utf8.encode('# 夜航船\n\n正文。')));

      expect(book.title, '夜航船');
    });
  });

  group('导入边界', () {
    test('不支持的扩展名被拒，并说明支持哪些', () async {
      final String path = await write('fake.pdf', <int>[0x25, 0x50, 0x44, 0x46]);
      await expectLater(
        TxtParser().parseFile(path),
        throwsA(isA<BookFileRejected>()
            .having((BookFileRejected e) => e.message, 'message', contains('不支持的文件类型'))
            .having((BookFileRejected e) => e.message, 'message', contains('pdf'))),
      );
    });

    test('看起来是二进制的 .txt 被拒（错误信息说得清是什么问题）', () async {
      final String path = await write('weird.txt', <int>[1, 2, ...List<int>.filled(200, 0)]);
      await expectLater(
        TxtParser().parseFile(path),
        throwsA(isA<TextDecodeException>()
            .having((TextDecodeException e) => e.message, 'message', contains('不是文本'))),
      );
    });

    test('空文件被拒', () async {
      final String path = await write('empty.txt', <int>[]);
      await expectLater(
        TxtParser().parseFile(path),
        throwsA(isA<BookFileRejected>()),
      );
    });

    test('文件不存在被拒', () async {
      await expectLater(
        TxtParser().parseFile('${dir.path}${Platform.pathSeparator}nope.txt'),
        throwsA(isA<BookFileRejected>()
            .having((BookFileRejected e) => e.message, 'message', contains('不存在'))),
      );
    });

    test('白名单覆盖计划书里承诺的格式', () {
      expect(
        kSupportedBookExtensions,
        containsAll(<String>['txt', 'md', 'markdown', 'docx']),
      );
    });
  });
}
