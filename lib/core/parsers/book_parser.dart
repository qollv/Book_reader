import 'dart:io';

import 'package:novel_reader/core/parsers/docx_parser.dart';
import 'package:novel_reader/core/parsers/markdown_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/parsers/txt_parser.dart';

/// 书籍文件解析器：本地路径 → 规范化书籍结构。
abstract class BookParser {
  Future<ParsedBook> parseFile(String path);
}

/// 按扩展名选择解析器。未知扩展名按 txt 处理（容错优先）。
BookParser parserForFile(String path) {
  final String lower = path.toLowerCase();
  if (lower.endsWith('.docx')) {
    return DocxParser();
  }
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return MarkdownParser();
  }
  return TxtParser();
}

/// 从文件内容猜书名：取第一个非空行，过长则视为正文。
String guessTitle(List<String> firstLines, String fallback) {
  for (String line in firstLines) {
    final String trimmed = line.trim();
    if (trimmed.isNotEmpty && trimmed.length <= 30) {
      return trimmed;
    }
    if (trimmed.isNotEmpty) {
      break;
    }
  }
  return fallback;
}

/// 按扩展名生成 fallback 书名（文件名去扩展名）。
String fileNameTitle(String path) {
  final File file = File(path);
  final String name = file.uri.pathSegments.last;
  final int dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
