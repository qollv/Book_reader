import 'dart:io';

import 'package:archive/archive.dart';
import 'package:novel_reader/core/parsers/book_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:xml/xml.dart';

/// docx 解析：解压 word/document.xml，按 w:p 提取段落。
///
/// Word 用段落样式表达标题（w:pStyle 含 Heading / 标题），
/// 这里把 1~2 级标题当作章节边界，其余按正文处理。
class DocxParser implements BookParser {
  @override
  Future<ParsedBook> parseFile(String path) async {
    final List<int> bytes = await File(path).readAsBytes();
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final ArchiveFile? document = _findDocumentXml(archive);
    if (document == null) {
      throw const FormatException('docx 中缺少 word/document.xml');
    }

    final String xmlText = String.fromCharCodes(document.content as List<int>);
    final XmlDocument document2 = XmlDocument.parse(xmlText);
    final List<String> paragraphs = <String>[];
    final List<bool> headingFlags = <bool>[];

    for (XmlElement element in document2.findAllElements('w:p')) {
      final String text = element.findElements('w:t').map((XmlElement t) => t.innerText).join();
      if (text.trim().isEmpty) {
        continue;
      }
      paragraphs.add(text.trim());
      headingFlags.add(_isHeading(element));
    }

    final String title = paragraphs.isNotEmpty && paragraphs.first.length <= 30
        ? paragraphs.first
        : fileNameTitle(path);

    final List<ParsedChapter> chapters = <ParsedChapter>[];
    List<ParagraphBlock> current = <ParagraphBlock>[];
    String currentTitle = '正文';
    bool titleSkipped = false;

    for (int i = 0; i < paragraphs.length; i++) {
      final String text = paragraphs[i];
      if (!titleSkipped && i == 0 && text == title) {
        titleSkipped = true;
        continue;
      }
      if (headingFlags[i] && current.isNotEmpty) {
        chapters.add(ParsedChapter(title: currentTitle, blocks: current));
        currentTitle = text;
        current = <ParagraphBlock>[];
        continue;
      }
      if (headingFlags[i]) {
        currentTitle = text;
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

  bool _isHeading(XmlElement paragraph) {
    for (XmlElement style in paragraph.findElements('w:pStyle')) {
      final String value = style.getAttribute('w:val') ?? '';
      final String lower = value.toLowerCase();
      if (lower.contains('heading') || lower.contains('标题')) {
        return true;
      }
    }
    return false;
  }
}
