// 复现用测试 2（分析工具生成，不属于原仓库）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/txt_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:xml/xml.dart';

void main() {
  test('R8 xml findElements vs findAllElements 语义', () {
    const String src = '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:t>正文文本</w:t></w:r></w:p>';
    final XmlElement p = XmlDocument.parse(src).rootElement;
    print('R8 findElements(w:t)     = ${p.findElements('w:t').map((e) => e.innerText).toList()}');
    print('R8 findAllElements(w:t)  = ${p.findAllElements('w:t').map((e) => e.innerText).toList()}');
    print('R8 findElements(w:pStyle)= ${p.findElements('w:pStyle').length} / '
        'findAllElements=${p.findAllElements('w:pStyle').length}');
  });

  test('R9 docx 正文编码方式', () {
    final List<int> utf8Bytes = utf8.encode('<w:t>第一章 起风了</w:t>');
    final String asFromCharCodes = String.fromCharCodes(utf8Bytes);
    final String asUtf8 = utf8.decode(utf8Bytes);
    print('R9 fromCharCodes = $asFromCharCodes');
    print('R9 utf8.decode   = $asUtf8');
  });

  test('R11 txt 书名行与空行', () async {
    final Directory dir = await Directory.systemTemp.createTemp('repro_txt2_');
    const List<String> cases = <String>[
      '无名小说\n正文一。\n正文二。',
      '\n无名小说\n正文一。\n正文二。',
      '\n\n无名小说\n正文一。\n正文二。',
      '无名小说\n\n正文一。\n正文二。',
    ];
    for (int i = 0; i < cases.length; i++) {
      final String path = '${dir.path}${Platform.pathSeparator}case$i.txt';
      await File(path).writeAsString(cases[i], encoding: utf8);
      final ParsedBook book = await TxtParser().parseFile(path);
      print('R11 case$i title="${book.title}" chapters=${book.chapters.length} '
          'firstBlocks=${book.chapters.first.blocks.map((ParagraphBlock b) => b.text).take(3).toList()}');
    }
  });
}
