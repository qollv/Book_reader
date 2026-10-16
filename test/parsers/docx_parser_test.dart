import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/core/parsers/docx_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';

/// 构造最小 docx：zip + 三件套 OOXML。
Future<File> _writeDocx(String documentXml, String path) async {
  final List<int> bytes = utf8.encode(documentXml);
  final Archive archive = Archive()
    ..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  final File file = File(path);
  await file.writeAsBytes(ZipEncoder().encode(archive)!);
  return file;
}

const String _minimalDocx = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:body>'
    '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第一章 起风了</w:t></w:r></w:p>'
    '<w:p><w:r><w:t>这是正文第一段，包含中文。</w:t></w:r></w:p>'
    '<w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>第二章 落雨</w:t></w:r></w:p>'
    '<w:p><w:r><w:t>正文第二段。</w:t></w:r></w:p>'
    '</w:body></w:document>';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docx_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // TC-01/02：DEF-01（findElements 取不到嵌套节点）+ DEF-02（UTF-8 解码）
  test('最小 docx 正确解析出中文标题与正文', () async {
    final File file = await _writeDocx(_minimalDocx, '${tempDir.path}/min.docx');
    final ParsedBook book = await DocxParser().parseFile(file.path);

    expect(book.title, '第一章 起风了');
    expect(book.chapters, hasLength(2));
    expect(book.chapters[0].title, '第一章 起风了');
    expect(book.chapters[1].title, '第二章 落雨');

    // 中文必须原样，不能是乱码也不能为空
    final List<String> firstTexts =
        book.chapters[0].blocks.map((ParagraphBlock b) => b.text).toList();
    expect(firstTexts, contains('这是正文第一段，包含中文。'));
    expect(firstTexts, contains('第一章 起风了'));
    expect(book.chapters[0].blocks.first.kind, ParagraphKind.heading);
  });

  test('缺少 document.xml 时抛中文 ImportException', () async {
    final File file = File('${tempDir.path}/empty.docx');
    final Archive archive = Archive()
      ..addFile(ArchiveFile('other.txt', 3, utf8.encode('abc')));
    await file.writeAsBytes(ZipEncoder().encode(archive)!);
    await expectLater(
      DocxParser().parseFile(file.path),
      throwsA(isA<ImportException>().having(
        (ImportException e) => e.message,
        'message',
        '文件不是有效的 docx，请确认文件格式',
      )),
    );
  });

  test('伪 docx（非 zip 二进制）抛中文 ImportException（DEF-10）', () async {
    final File file = File('${tempDir.path}/fake.docx');
    // 全字节范围二进制，非 zip 容器：archive 层原本抛英文技术异常
    await file.writeAsBytes(List<int>.generate(512, (int i) => i % 256));
    await expectLater(
      DocxParser().parseFile(file.path),
      throwsA(isA<ImportException>().having(
        (ImportException e) => e.message,
        'message',
        '文件不是有效的 docx，请确认文件格式',
      )),
    );
  });
}
