// 复现用测试 8：非 UTF-8 编码 txt 导入（分析工具生成）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/txt_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';

void main() {
  test('R19 GBK / BOM / 二进制文件的 txt 解析', () async {
    final Directory dir = await Directory.systemTemp.createTemp('repro_enc_');

    // GBK 编码的「第一章 起风了\n正文一。」
    final List<int> gbk = <int>[
      0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2, 0x20, 0xC6, 0xF0, 0xB7, 0xE7, 0xC1, 0xCB, 0x0A,
      0xD5, 0xFD, 0xCE, 0xC4, 0xD2, 0xBB, 0xA1, 0xA3,
    ];
    final String gbkPath = '${dir.path}${Platform.pathSeparator}gbk.txt';
    await File(gbkPath).writeAsBytes(gbk);
    try {
      final ParsedBook book = await TxtParser().parseFile(gbkPath);
      print('R19 GBK 解析成功 title="${book.title}" blocks='
          '${book.chapters.first.blocks.map((ParagraphBlock b) => b.text).toList()}');
    } catch (error) {
      print('R19 GBK 解析 THREW: ${error.runtimeType}: $error');
    }

    // 带 UTF-8 BOM 的 txt
    final String bomPath = '${dir.path}${Platform.pathSeparator}bom.txt';
    await File(bomPath).writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('书名\n正文一。')]);
    final ParsedBook bomBook = await TxtParser().parseFile(bomPath);
    print('R19 BOM title=${bomBook.title.codeUnits} raw="${bomBook.title}"');

    // 二进制文件（模拟误选的 pdf）按 txt 处理
    final String binPath = '${dir.path}${Platform.pathSeparator}fake.pdf';
    await File(binPath).writeAsBytes(List<int>.generate(96, (int i) => i * 3 % 256));
    try {
      final ParsedBook bin = await TxtParser().parseFile(binPath);
      print('R19 二进制文件 解析成功 title="${bin.title}" chapters=${bin.chapters.length} '
          'blocks=${bin.chapters.first.blocks.length}');
    } catch (error) {
      print('R19 二进制文件 THREW: ${error.runtimeType}: $error');
    }
  });
}
