import 'dart:convert';
import 'dart:io';

import 'package:novel_reader/core/parsers/book_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/text/text_normalizer.dart';

/// txt 解析：章节识别 + 硬换行合并。
class TxtParser implements BookParser {
  // 「第x章/节/卷/回」开头视为新章节标题
  static final RegExp _chapterPattern = RegExp(
    r'^\s*第[\s零一二三四五六七八九十百千万0-9]+[章节卷回部篇].*$',
  );

  @override
  Future<ParsedBook> parseFile(String path) async {
    final String raw = await File(path).readAsString(encoding: utf8);
    final List<String> lines = const LineSplitter().convert(raw);

    final String title = guessTitle(lines, fileNameTitle(path));
    final List<String> body = _dropTitleLines(lines, title);

    final List<ParsedChapter> chapters = <ParsedChapter>[];
    List<ParagraphBlock> current = <ParagraphBlock>[];
    List<String> pendingLines = <String>[];
    String currentTitle = '正文';

    for (String line in body) {
      if (_chapterPattern.hasMatch(line)) {
        _flush(pendingLines, current);
        if (current.isNotEmpty) {
          chapters.add(ParsedChapter(title: currentTitle, blocks: current));
        }
        currentTitle = line.trim();
        current = <ParagraphBlock>[];
        continue;
      }
      if (line.trim().isEmpty) {
        _flush(pendingLines, current);
        continue;
      }
      pendingLines.add(line);
    }
    _flush(pendingLines, current);
    if (current.isNotEmpty) {
      chapters.add(ParsedChapter(title: currentTitle, blocks: current));
    }
    if (chapters.isEmpty) {
      chapters.add(const ParsedChapter(title: '正文', blocks: <ParagraphBlock>[]));
    }

    return ParsedBook(title: title, author: '', chapters: chapters);
  }

  /// 把累积的原始行合并成规范段落：空行分段，段内硬换行按句读续行。
  void _flush(List<String> pendingLines, List<ParagraphBlock> current) {
    if (pendingLines.isEmpty) {
      return;
    }
    final String rawParagraph = pendingLines.join('\n');
    for (String paragraph in TextNormalizer.reflow(rawParagraph)) {
      current.add(ParagraphBlock(text: paragraph, kind: ParagraphKind.paragraph));
    }
    pendingLines.clear();
  }

  /// 已用作书名的前几行从正文中去掉，避免开头重复。
  List<String> _dropTitleLines(List<String> lines, String title) {
    int dropped = 0;
    for (String line in lines) {
      if (dropped >= 2) {
        break;
      }
      if (line.trim() == title || line.trim().isEmpty) {
        dropped++;
        continue;
      }
      break;
    }
    return lines.skip(dropped).toList();
  }
}
