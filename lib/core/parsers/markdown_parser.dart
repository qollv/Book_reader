import 'dart:convert';
import 'dart:io';

import 'package:novel_reader/core/parsers/book_file_guard.dart';
import 'package:novel_reader/core/parsers/book_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/text/byte_text_decoder.dart';

/// Markdown 解析：# / ## 视为章节标题，### 视为段内标题，
/// 引用/列表/代码块保留结构，行内 Markdown 语法被剥离。
class MarkdownParser implements BookParser {
  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _quote = RegExp(r'^>\s?(.*)$');
  static final RegExp _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
  static final RegExp _ordered = RegExp(r'^\s*\d+[.、]\s+(.*)$');

  // 行内语法：顺序敏感，先长后短（图片 → 链接 → 行内代码 → 粗体 → 斜体）
  static final RegExp _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
  static final RegExp _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
  static final RegExp _code = RegExp(r'`([^`]+)`');
  static final RegExp _bold = RegExp(r'\*\*([^*\n]+)\*\*');
  static final RegExp _italicStar = RegExp(r'\*([^*\n]+)\*');

  /// 下划线斜体只在**词边界**生效。
  ///
  /// 否则 `snake_case_name` 会被当成斜体、把中间吃掉。
  /// 用 `\b` 而不是环视断言，兼容性最好。
  static final RegExp _italicUnderscore = RegExp(r'\b_([^_\n]+)_\b');

  @override
  Future<ParsedBook> parseFile(String path) async {
    final File file = await checkBookFile(path);
    final DecodedText decoded = decodeBookFileBytes(await file.readAsBytes());
    final List<String> lines = const LineSplitter().convert(decoded.text);

    // 猜书名时先剥掉行内/标题语法：否则 `# 夜航船` 会连井号一起进书名，
    // 而且后面 `_skipTitleHeading` 拿剥好的文本去比对也对不上，
    // 结果就是书名带 `#`、正文里还重复一遍标题
    final String title = guessTitle(
      lines.map(_titleCandidate).toList(growable: false),
      fileNameTitle(path),
    );
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
        current.add(ParagraphBlock(
            text: '• ${stripInline(bullet.group(1)!)}', kind: ParagraphKind.paragraph));
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

  /// 用来猜书名的候选文本：剥掉 `#` 前缀与行内语法。
  static String _titleCandidate(String line) {
    final String trimmed = line.trim();
    final RegExpMatch? heading = _heading.firstMatch(trimmed);
    if (heading != null) {
      return stripInline(heading.group(2)!);
    }
    return stripInline(trimmed);
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
  ///
  /// 这里有原来的一个硬伤：`String.replaceAll` 的替换串是**字面量**，
  /// 不支持 `$1` 反向引用（只有 `replaceAllMapped` 支持）。
  /// 所以旧实现把 `**粗体**` 变成了字面量 `$1`，正文直接被污染。
  /// 现在全部走 [RegExpMatch] 显式取组，不再依赖反向引用。
  static String stripInline(String text) {
    String result = text;
    result = result.replaceAllMapped(_image, (Match m) => m.group(1) ?? '');
    result = result.replaceAllMapped(_link, (Match m) => m.group(1) ?? '');
    result = result.replaceAllMapped(_code, (Match m) => m.group(1) ?? '');
    result = result.replaceAllMapped(_bold, (Match m) => m.group(1) ?? '');
    result = result.replaceAllMapped(_italicStar, (Match m) => m.group(1) ?? '');
    result = result.replaceAllMapped(_italicUnderscore, (Match m) => m.group(1) ?? '');
    return result.trim();
  }
}
