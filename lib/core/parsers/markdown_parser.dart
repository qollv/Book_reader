import 'dart:convert';
import 'dart:io';

import 'package:novel_reader/core/parsers/book_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';

/// Markdown 解析：# / ## 视为章节标题，### 视为段内标题，
/// 引用/列表/代码块保留结构，行内 Markdown 语法被剥离。
class MarkdownParser implements BookParser {
  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _quote = RegExp(r'^>\s?(.*)$');
  static final RegExp _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
  static final RegExp _ordered = RegExp(r'^\s*\d+[.、]\s+(.*)$');
  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*');
  static final RegExp _italic = RegExp(r'\*(.+?)\*|_(.+?)_');
  static final RegExp _code = RegExp(r'`([^`]+)`');
  static final RegExp _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
  static final RegExp _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');

  @override
  Future<ParsedBook> parseFile(String path) async {
    final String raw = await File(path).readAsString(encoding: utf8);
    final List<String> lines = const LineSplitter().convert(raw);

    final String title = guessTitle(lines, fileNameTitle(path));
    final List<String> body = _skipTitleHeading(lines, title);

    final List<ParsedChapter> chapters = <ParsedChapter>[];
    List<ParagraphBlock> current = <ParagraphBlock>[];
    String currentTitle = '正文';

    for (int i = 0; i < body.length; i++) {
      final String trimmed = body[i].trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.startsWith('```')) {
        i = _appendCodeBlock(body, i, current);
        continue;
      }
      final RegExpMatch? heading = _heading.firstMatch(trimmed);
      if (heading != null) {
        final int level = heading.group(1)!.length;
        final String text = stripInline(heading.group(2)!);
        if (level <= 2) {
          if (current.isNotEmpty) {
            chapters.add(ParsedChapter(title: currentTitle, blocks: current));
          }
          currentTitle = text;
          current = <ParagraphBlock>[];
        }
        current.add(ParagraphBlock(text: text, kind: ParagraphKind.heading, headingLevel: level));
        continue;
      }
      final RegExpMatch? quote = _quote.firstMatch(trimmed);
      if (quote != null) {
        current.add(ParagraphBlock(text: stripInline(quote.group(1)!), kind: ParagraphKind.quote));
        continue;
      }
      final RegExpMatch? bullet = _bullet.firstMatch(trimmed);
      if (bullet != null) {
        current.add(ParagraphBlock(text: '• ' + stripInline(bullet.group(1)!), kind: ParagraphKind.paragraph));
        continue;
      }
      final RegExpMatch? ordered = _ordered.firstMatch(trimmed);
      if (ordered != null) {
        current.add(ParagraphBlock(text: stripInline(ordered.group(1)!), kind: ParagraphKind.paragraph));
        continue;
      }
      current.add(ParagraphBlock(text: stripInline(trimmed), kind: ParagraphKind.paragraph));
    }
    if (current.isNotEmpty) {
      chapters.add(ParsedChapter(title: currentTitle, blocks: current));
    }
    if (chapters.isEmpty) {
      chapters.add(const ParsedChapter(title: '正文', blocks: <ParagraphBlock>[]));
    }
    return ParsedBook(title: title, author: '', chapters: chapters);
  }

  /// 收集 ``` 围栏代码块，返回围栏结束行的下标（未闭合则到文末）。
  int _appendCodeBlock(List<String> lines, int startIndex, List<ParagraphBlock> out) {
    final StringBuffer buffer = StringBuffer();
    int index = startIndex + 1;
    while (index < lines.length && !lines[index].trim().startsWith('```')) {
      buffer.writeln(lines[index]);
      index++;
    }
    out.add(ParagraphBlock(text: buffer.toString().trimRight(), kind: ParagraphKind.code));
    return index;
  }

  /// 去掉与书名相同的标题行（# 标题），避免书名在正文里重复出现。
  List<String> _skipTitleHeading(List<String> lines, String title) {
    final List<String> result = <String>[];
    bool titleRemoved = false;
    for (String line in lines) {
      final RegExpMatch? heading = _heading.firstMatch(line.trim());
      if (!titleRemoved && heading != null && stripInline(heading.group(2)!) == title) {
        titleRemoved = true;
        continue;
      }
      result.add(line);
    }
    return result;
  }

  /// 剥离行内 Markdown 语法，只留纯文本。
  static String stripInline(String text) {
    String result = _image.replaceAll(text, '$1');
    result = _link.replaceAll(result, '$1');
    result = _bold.replaceAll(result, '$1');
    result = _italic.replaceAll(result, '$1$2');
    result = _code.replaceAll(result, '$1');
    return result.trim();
  }
}
