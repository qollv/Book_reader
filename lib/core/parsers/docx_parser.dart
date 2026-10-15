import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_reader/core/parsers/book_file_guard.dart';
import 'package:novel_reader/core/parsers/book_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/text/byte_text_decoder.dart';
import 'package:xml/xml.dart';

/// docx 解析：解压 word/document.xml，按 w:p 提取段落。
///
/// 这份实现修掉了三个会让 docx 导入彻底失效的问题：
///
/// 1. **取值用了 `findElements`**。它只找**直接子节点**，而 docx 里
///    `<w:t>` 在 `<w:r>` 里、`<w:pStyle>` 在 `<w:pPr>` 里，都隔了一层，
///    于是每段文本都是空串、全被丢掉 —— 导入结果是「一本空书」。
///    现在统一走 [XmlNode.descendants] 取后代。
/// 2. **用 `String.fromCharCodes` 解 XML**。那会把 UTF-8 字节逐个当码点，
///    中文全变乱码。现在按 BOM/UTF-8 解码。
/// 3. **按 `w:` 前缀匹配元素名**。前缀只是惯例，合法文档可以绑别的前缀，
///    所以改成按「命名空间 + 本地名」匹配。
class DocxParser implements BookParser {
  /// WordprocessingML 主命名空间。
  static const String _wordNamespace =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// Word 里「正文」的 outlineLvl 取值，大于它是标题。
  static const int _bodyOutlineLevel = 9;

  @override
  Future<ParsedBook> parseFile(String path) async {
    final File file = await checkBookFile(path);
    final List<int> bytes = await file.readAsBytes();
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final ArchiveFile? document = _findDocumentXml(archive);
    if (document == null) {
      throw const BookFileRejected('这个 docx 里没有 word/document.xml，可能不是有效的 Word 文档');
    }

    final Uint8List xmlBytes = Uint8List.fromList(document.content as List<int>);
    // XML 自带 BOM 时按 BOM 走；docx 规范是 UTF-8，兜底用容错 UTF-8
    final DecodedText decoded = decodeWithBom(xmlBytes) ??
        DecodedText(decodeLenient(utf8, xmlBytes), 'utf-8');
    final XmlDocument xml = XmlDocument.parse(decoded.text);

    final List<String> paragraphs = <String>[];
    final List<int?> headingLevels = <int?>[];
    for (final XmlElement element in xml.descendants.whereType<XmlElement>()) {
      if (!_isWord(element, 'p')) {
        continue;
      }
      final String text = _paragraphText(element).trim();
      if (text.isEmpty) {
        continue;
      }
      paragraphs.add(text);
      headingLevels.add(_headingLevel(element));
    }

    if (paragraphs.isEmpty) {
      throw const BookFileRejected('这个 docx 里没有可读的正文（可能是纯图片或纯表格文档）');
    }

    // 首段是标题样式时，它是章节名而不是书名，书名退回文件名
    final String title = headingLevels.first == null && paragraphs.first.length <= 30
        ? paragraphs.first
        : fileNameTitle(path);

    return ParsedBook(
      title: title,
      author: '',
      chapters: _buildChapters(paragraphs, headingLevels, title),
    );
  }

  List<ParsedChapter> _buildChapters(
    List<String> paragraphs,
    List<int?> headingLevels,
    String title,
  ) {
    final List<ParsedChapter> chapters = <ParsedChapter>[];
    List<ParagraphBlock> current = <ParagraphBlock>[];
    String currentTitle = '正文';
    bool titleSkipped = false;

    for (int i = 0; i < paragraphs.length; i++) {
      final String text = paragraphs[i];
      final int? level = headingLevels[i];

      if (!titleSkipped && i == 0 && text == title) {
        titleSkipped = true;
        continue;
      }
      // 1~2 级标题作为章节边界，与 markdown 解析保持一致的口径
      if (level != null && level <= 2) {
        if (current.isNotEmpty) {
          chapters.add(ParsedChapter(title: currentTitle, blocks: current));
        }
        currentTitle = text;
        current = <ParagraphBlock>[];
        continue;
      }
      if (level != null) {
        current.add(ParagraphBlock(text: text, kind: ParagraphKind.heading, headingLevel: level));
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
    return chapters;
  }

  ArchiveFile? _findDocumentXml(Archive archive) {
    for (final ArchiveFile file in archive.files) {
      if (file.name == 'word/document.xml') {
        return file;
      }
    }
    return null;
  }

  /// 收集段落内文本，按文档顺序处理 `w:t` / `w:tab` / `w:br`。
  ///
  /// `w:instrText`、`w:delText` 不参与（分别是域代码和被删除的修订文本），
  /// 绘图里的 `a:t` 也因命名空间不同被排除。
  static String _paragraphText(XmlElement paragraph) {
    final StringBuffer buffer = StringBuffer();
    for (final XmlNode node in paragraph.descendants) {
      if (node is! XmlElement) {
        continue;
      }
      if (_isWord(node, 't')) {
        buffer.write(node.innerText);
      } else if (_isWord(node, 'tab')) {
        buffer.write('\t');
      } else if (_isWord(node, 'br')) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  /// 推断标题级别（1~6），非标题返回 null。
  ///
  /// 两条依据：`w:pStyle`（Heading1 / 标题 1）与 `w:outlineLvl`（大纲级别）。
  /// 只认前者会漏掉用大纲级别排版的大量真实文档。
  static int? _headingLevel(XmlElement paragraph) {
    for (final XmlNode node in paragraph.descendants) {
      if (node is! XmlElement) {
        continue;
      }
      if (_isWord(node, 'outlineLvl')) {
        final int? level = int.tryParse(_valAttribute(node) ?? '');
        if (level != null && level >= 0 && level < _bodyOutlineLevel) {
          return (level + 1).clamp(1, 6);
        }
      }
      if (_isWord(node, 'pStyle')) {
        final String value = (_valAttribute(node) ?? '').toLowerCase();
        final RegExpMatch? numbered =
            RegExp(r'(?:heading|标题)\s*([1-9])').firstMatch(value);
        if (numbered != null) {
          return int.parse(numbered.group(1)!).clamp(1, 6);
        }
        if (value.contains('heading') || value.contains('标题')) {
          return 1;
        }
      }
    }
    return null;
  }

  /// 按「本地名」取 `w:val` 属性，不依赖文档用的是哪个前缀。
  static String? _valAttribute(XmlElement element) {
    for (final XmlAttribute attribute in element.attributes) {
      if (attribute.name.local == 'val') {
        return attribute.value;
      }
    }
    return null;
  }

  /// 元素是否是 Word 命名空间下的指定元素。
  static bool _isWord(XmlElement element, String local) {
    if (element.name.local != local) {
      return false;
    }
    final String? namespace = element.name.namespaceUri;
    if (namespace != null) {
      return namespace == _wordNamespace;
    }
    // 命名空间没解析出来时退回前缀判断，避免整份文档被判成没有正文
    return element.name.prefix == 'w' || element.name.prefix == null;
  }
}
