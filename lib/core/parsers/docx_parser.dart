import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:novel_reader/core/parsers/book_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:xml/xml.dart';

/// docx 解析：解压 word/document.xml，按 w:p 提取段落。
///
/// Word 用段落样式表达标题（w:pStyle 含 Heading / 标题）：
/// 1~2 级标题既作章节边界，也作为标题块进入正文（与 md 解析一致）。
class DocxParser implements BookParser {
  @override
  Future<ParsedBook> parseFile(String path) async {
    final List<int> bytes = await File(path).readAsBytes();
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final ArchiveFile? document = _findDocumentXml(archive);
    if (document == null) {
      throw const FormatException('docx 中缺少 word/document.xml');
    }

    // document.xml 声明为 UTF-8，必须按 UTF-8 解码（fromCharCodes 会得到乱码）
    final String xmlText = utf8.decode(document.content as List<int>, allowMalformed: true);
    final XmlDocument documentRoot = XmlDocument.parse(xmlText);
    final List<String> paragraphs = <String>[];
    final List<int> headingLevels = <int>[];

    for (XmlElement element in documentRoot.findAllElements('w:p')) {
      // w:t 嵌套在 w:p > w:r > w:t，必须用 findAllElements 递归查找
      final String text = element.findAllElements('w:t').map((XmlElement t) => t.innerText).join();
      if (text.trim().isEmpty) {
        continue;
      }
      paragraphs.add(text.trim());
      headingLevels.add(_headingLevel(element));
    }

    final String title = paragraphs.isNotEmpty && paragraphs.first.length <= 30
        ? paragraphs.first
        : fileNameTitle(path);

    // 首段是标题时它就是第一章标题，不从正文剔除；首段是普通文本（被用作书名）时才剔除
    final bool firstIsHeading =
        paragraphs.isNotEmpty && headingLevels.isNotEmpty && headingLevels[0] > 0;

    final List<ParsedChapter> chapters = <ParsedChapter>[];
    List<ParagraphBlock> current = <ParagraphBlock>[];
    String currentTitle = '正文';

    for (int i = 0; i < paragraphs.length; i++) {
      final String text = paragraphs[i];
      if (i == 0 && !firstIsHeading && text == title) {
        continue;
      }
      if (headingLevels[i] > 0) {
        if (current.isNotEmpty) {
          chapters.add(ParsedChapter(title: currentTitle, blocks: current));
          current = <ParagraphBlock>[];
        }
        currentTitle = text;
        current.add(ParagraphBlock(
          text: text,
          kind: ParagraphKind.heading,
          headingLevel: headingLevels[i],
        ));
        continue;
      }
      current.add(ParagraphBlock(text: text, kind: ParagraphKind.paragraph));
    }
    if (current.isNotEmpty) {
      chapters.add(ParsedChapter(title: currentTitle, blocks: current));
    }
    if (chapters.isEmpty) {
      chapters.add(const ParsedChapter(title: '正文', blocks: <ParagraphBlock>[]));
    }
    return ParsedBook(title: title, author: '', chapters: chapters);
  }

  ArchiveFile? _findDocumentXml(Archive archive) {
    for (ArchiveFile file in archive.files) {
      if (file.name == 'word/document.xml') {
        return file;
      }
    }
    return null;
  }

  /// 返回标题级别（1/2），非标题返回 0。
  /// pStyle 嵌套在 w:p > w:pPr > w:pStyle，需递归查找。
  int _headingLevel(XmlElement paragraph) {
    for (XmlElement style in paragraph.findAllElements('w:pStyle')) {
      final String value = (style.getAttribute('w:val') ?? '').toLowerCase();
      if (value.contains('标题') || value.contains('heading')) {
        if (value.contains('2') || value.contains('二')) {
          return 2;
        }
        return 1;
      }
    }
    return 0;
  }
}
