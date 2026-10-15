// 复现用测试（分析工具生成，不属于原仓库）。每个 test 只打印观测结果。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/docx_parser.dart';
import 'package:novel_reader/core/parsers/markdown_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/parsers/txt_parser.dart';
import 'package:novel_reader/core/text/text_normalizer.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/models/reading_progress.dart';

Future<String> _writeDocx(Directory dir) async {
  const String documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>'
      '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第一章 起风了</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>这是正文第一段，包含中文。</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>第二章 落雨</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>正文第二段。</w:t></w:r></w:p>'
      '</w:body></w:document>';
  final List<int> bytes = utf8.encode(documentXml);
  final Archive archive = Archive()..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  final List<int>? zip = ZipEncoder().encode(archive);
  final String path = '${dir.path}${Platform.pathSeparator}book.docx';
  await File(path).writeAsBytes(zip!);
  return path;
}

void main() {
  test('R1 docx 解析结果', () async {
    final Directory dir = await Directory.systemTemp.createTemp('repro_docx_');
    final String path = await _writeDocx(dir);
    try {
      final ParsedBook book = await DocxParser().parseFile(path);
      print('R1 title=${book.title}');
      print('R1 chapters=${book.chapters.length}');
      for (final chapter in book.chapters) {
        print('R1   chapter title="${chapter.title}" blocks=${chapter.blocks.length} '
            'texts=${chapter.blocks.map((ParagraphBlock b) => b.text).toList()}');
      }
    } catch (error) {
      print('R1 THREW: $error');
    }
  });

  test('R2 markdown 行内语法剥离', () {
    for (final String input in <String>[
      'snake_case_name',
      'a_b_c_d',
      '变量 foo_bar 与 baz_qux',
      '**粗体** 与 *斜体*',
      r'反斜杠 \$1 与 ${x}',
      'http://a.com/b_c_d?x=y_z',
    ]) {
      print('R2 in="$input" out="${MarkdownParser.stripInline(input)}"');
    }
  });

  test('R3 txt 书名行删除', () async {
    final Directory dir = await Directory.systemTemp.createTemp('repro_txt_');
    final String path = '${dir.path}${Platform.pathSeparator}book.txt';
    await File(path).writeAsString('\n\n第一章 起风了\n正文一。\n正文二。');
    final ParsedBook book = await TxtParser().parseFile(path);
    print('R3 title="${book.title}"');
    for (final ParsedChapter chapter in book.chapters) {
      print('R3   chapter "${chapter.title}" '
          'texts=${chapter.blocks.map((ParagraphBlock b) => b.text).toList()}');
    }
  });

  test('R4 TextNormalizer 边界', () {
    print('R4 crlf=${TextNormalizer.reflow('第一行\r\n第二行').toList()}');
    print('R4 quote=${TextNormalizer.reflow('”续行测试\n第二行').toList()}');
    print('R4 ascii=${TextNormalizer.reflow('hello\nworld').toList()}');
  });

  test('R5 ReaderSettings.decode 非法/越界数据', () {
    final String bad = jsonEncode(<String, Object?>{
      'theme_mode': 'dark',
      'palette_index': 9,
      'font_family': 'system',
      'font_scale': 6.0,
      'line_height': 0.2,
      'margin_index': 7,
      'page_animation': 'slide',
    });
    final ReaderSettings decoded = ReaderSettings.decode(bad);
    print('R5 paletteIndex=${decoded.paletteIndex} marginIndex=${decoded.marginIndex} '
        'fontScale=${decoded.fontScale} lineHeight=${decoded.lineHeight}');
    try {
      print('R5 horizontalMargin=${decoded.horizontalMargin}');
    } catch (error) {
      print('R5 horizontalMargin THREW: $error');
    }
    try {
      print('R5 decode(missing keys)=${ReaderSettings.decode('{"font_scale":1.2}')}');
    } catch (error) {
      print('R5 decode(missing keys) THREW: $error');
    }
    try {
      print('R5 decode(garbage)=${ReaderSettings.decode('not json')}');
    } catch (error) {
      print('R5 decode(garbage) THREW: $error');
    }
  });

  test('R6 模型 fromJson/fromRow 类型假设', () {
    try {
      print('R6 block=${ParagraphBlock.fromJson(<String, Object?>{'text': 'abc', 'kind': 'paragraph'})}');
    } catch (error) {
      print('R6 ParagraphBlock.fromJson(missing level) THREW: $error');
    }
    try {
      print('R6 progress=${ReadingProgress.fromRow(<String, Object?>{
        'book_id': 'b',
        'chapter_index': 0,
        'paragraph_index': 0,
        'line_index': 0,
        'percent': 0,
        'updated_at': 0,
      })}');
    } catch (error) {
      print('R6 ReadingProgress.fromRow(int percent) THREW: $error');
    }
    try {
      print('R6 book=${Book.fromRow(<String, Object?>{'id': 'b', 'title': 't'})}');
    } catch (error) {
      print('R6 Book.fromRow(partial row) THREW: $error');
    }
  });

  test('R7 空内容 content.jsonl 与 fromJson', () {
    final String encoded = jsonEncode(
      const ParagraphBlock(text: '第一行\n第二行', kind: ParagraphKind.paragraph).toJson(),
    );
    print('R7 jsonEncode 后含裸换行=${encoded.contains('\n')} value=$encoded');
    print('R7 反解析=${ParagraphBlock.fromJson(jsonDecode(encoded) as Map<String, Object?>).text}');
  });
}
