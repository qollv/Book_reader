import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/core/parsers/book_file_guard.dart';
import 'package:novel_reader/core/parsers/docx_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';

/// docx 解析回归测试。
///
/// 背景：原实现用 `findElements` 取 `w:t` / `w:pStyle`，而这两个元素在
/// docx 里都**隔了一层**（`<w:p><w:r><w:t>`、`<w:p><w:pPr><w:pStyle>`），
/// 于是每段文本都是空串、标题样式也识别不到 —— 导入 norml 的 docx
/// 得到的是「一本空书」；再加上 `String.fromCharCodes` 解 XML，
/// 中文会全变乱码。这些用例逐个钉住修复后的行为。
const String _wordNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _documentXml(List<String> paragraphs, {String prefix = 'w'}) {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<$prefix:document xmlns:$prefix="$_wordNamespace"><$prefix:body>'
      '${paragraphs.join()}'
      '</$prefix:body></$prefix:document>';
}

/// 一个段落。[style] 与 [outline] 用来表达标题，[tab]/[br] 用来验证行内元素。
String _paragraph(
  String text, {
  String? style,
  int? outline,
  String prefix = 'w',
  bool tab = false,
  bool br = false,
}) {
  final StringBuffer properties = StringBuffer();
  if (outline != null) {
    properties.write('<$prefix:outlineLvl $prefix:val="$outline"/>');
  }
  if (style != null) {
    properties.write('<$prefix:pStyle $prefix:val="$style"/>');
  }
  final String pPr = properties.isEmpty ? '' : '<$prefix:pPr>$properties</$prefix:pPr>';
  // tab 放在文字之后：段首的制表/空格会被 trim 掉（那是缩进噪声，
  // 渲染端会自己加首行缩进），这里要验证的是段中的行内元素
  final String runs = <String>[
    '<$prefix:t>$text</$prefix:t>',
    if (tab) '<$prefix:tab/>',
    if (tab) '<$prefix:t>后段</$prefix:t>',
    if (br) '<$prefix:br/>',
    if (br) '<$prefix:t>第二行</$prefix:t>',
  ].join();
  return '<$prefix:p>$pPr<$prefix:r>$runs</$prefix:r></$prefix:p>';
}

Future<String> _writeDocx(Directory dir, String xml, {String name = 'book.docx'}) async {
  final List<int> bytes = utf8.encode(xml);
  final Archive archive = Archive()
    ..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  final List<int> zip = ZipEncoder().encode(archive)!;
  final String path = '${dir.path}${Platform.pathSeparator}$name';
  await File(path).writeAsBytes(zip);
  return path;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('docx_regression_');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('标题样式分章，正文完整且中文不乱码', () async {
    final String xml = _documentXml(<String>[
      _paragraph('第一章 起风了', style: 'Heading1'),
      _paragraph('这是正文第一段，包含中文。'),
      _paragraph('第二章 落雨', style: 'Heading2'),
      _paragraph('正文第二段。'),
    ]);
    final ParsedBook book = await DocxParser().parseFile(await _writeDocx(dir, xml));

    expect(book.chapters, hasLength(2), reason: '两个标题应当分成两章');

    // 中文必须逐字正确 —— 这条直接钉住 fromCharCodes 造成的乱码
    expect(book.chapters[0].blocks.single.text, '这是正文第一段，包含中文。');
    expect(book.chapters[1].title, '第二章 落雨');
    expect(book.chapters[1].blocks.single.text, '正文第二段。');
  });

  test('首段是标题样式时，书名退回文件名而不是用章节名', () async {
    final String xml = _documentXml(<String>[
      _paragraph('第一章 起风了', style: 'Heading1'),
      _paragraph('正文。'),
    ]);
    final ParsedBook book =
        await DocxParser().parseFile(await _writeDocx(dir, xml, name: '夜航船.docx'));

    expect(book.title, '夜航船');
    expect(book.chapters.single.title, '第一章 起风了');
  });

  test('没有标题样式时合成单章，首段当书名', () async {
    final String xml = _documentXml(<String>[
      _paragraph('夜航船'),
      _paragraph('正文一。'),
      _paragraph('正文二。'),
    ]);
    final ParsedBook book = await DocxParser().parseFile(await _writeDocx(dir, xml));

    expect(book.title, '夜航船');
    expect(book.chapters, hasLength(1));
    // 书名那一段不再重复出现在正文里
    expect(
      book.chapters.single.blocks.map((ParagraphBlock b) => b.text).toList(),
      <String>['正文一。', '正文二。'],
    );
  });

  test('只用 outlineLvl 表达标题也能识别', () async {
    final String xml = _documentXml(<String>[
      _paragraph('卷一 启程', outline: 0),
      _paragraph('正文甲。'),
      _paragraph('卷二 归途', outline: 1),
      _paragraph('正文乙。'),
    ]);
    final ParsedBook book = await DocxParser().parseFile(await _writeDocx(dir, xml));

    expect(book.chapters, hasLength(2));
    expect(book.chapters[0].title, '卷一 启程');
    expect(book.chapters[1].title, '卷二 归途');
  });

  test('outlineLvl=9（正文级别）不被误判成标题', () async {
    final String xml = _documentXml(<String>[
      _paragraph('书名'),
      _paragraph('正文一。', outline: 9),
      _paragraph('正文二。', outline: 9),
    ]);
    final ParsedBook book = await DocxParser().parseFile(await _writeDocx(dir, xml));

    expect(book.chapters, hasLength(1));
    expect(book.chapters.single.blocks, hasLength(2), reason: '正文不该被当成章节边界');
  });

  test('三级以上标题是段内标题而不是章节边界', () async {
    final String xml = _documentXml(<String>[
      _paragraph('第一章', style: 'Heading1'),
      _paragraph('小节', style: 'Heading3'),
      _paragraph('正文。'),
    ]);
    final ParsedBook book = await DocxParser().parseFile(await _writeDocx(dir, xml));

    expect(book.chapters, hasLength(1), reason: 'H3 不切章');
    final List<ParagraphBlock> blocks = book.chapters.single.blocks;
    expect(blocks.map((ParagraphBlock b) => b.kind).toList(),
        <ParagraphKind>[ParagraphKind.heading, ParagraphKind.paragraph]);
    expect(blocks.first.headingLevel, 3);
  });

  test('命名空间前缀不是 w 时仍能解析（前缀只是惯例）', () async {
    final String xml = _documentXml(
      <String>[
        _paragraph('第一章 起风了', style: 'Heading1', prefix: 'd'),
        _paragraph('正文。', prefix: 'd'),
      ],
      prefix: 'd',
    );
    final ParsedBook book = await DocxParser().parseFile(await _writeDocx(dir, xml));

    expect(book.chapters.single.blocks.single.text, '正文。');
    expect(book.chapters.single.title, '第一章 起风了');
  });

  test('w:tab 与 w:br 参与文本', () async {
    final String xml = _documentXml(<String>[
      _paragraph('书名'),
      _paragraph('前段', tab: true, br: true),
    ]);
    final ParsedBook book = await DocxParser().parseFile(await _writeDocx(dir, xml));

    final String text = book.chapters.single.blocks.single.text;
    expect(text, contains('\t'));
    expect(text, contains('\n'));
  });

  test('缺少 word/document.xml 时给出可读错误而不是抛内部异常', () async {
    final List<int> bytes = utf8.encode('not a docx');
    final Archive archive = Archive()
      ..addFile(ArchiveFile('other.xml', bytes.length, bytes));
    final String path = '${dir.path}${Platform.pathSeparator}bad.docx';
    await File(path).writeAsBytes(ZipEncoder().encode(archive)!);

    await expectLater(
      DocxParser().parseFile(path),
      throwsA(isA<BookFileRejected>()
          .having((BookFileRejected e) => e.message, 'message', contains('word/document.xml'))),
    );
  });

  test('只有空段落时给出可读错误（而不是返回一本空书）', () async {
    final String xml = _documentXml(<String>[_paragraph('   ')]);
    await expectLater(
      DocxParser().parseFile(await _writeDocx(dir, xml)),
      throwsA(isA<BookFileRejected>()),
    );
  });
}
