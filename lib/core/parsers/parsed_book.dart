/// 解析后的一段正文：文本 + 排版类型。
///
/// 类型决定渲染方式（标题加粗居中、引用缩进、代码等宽），也决定分页规则
/// （标题不与后文拆散）。
enum ParagraphKind { paragraph, heading, quote, code }

class ParagraphBlock {
  const ParagraphBlock({
    required this.text,
    required this.kind,
    this.headingLevel = 1,
  });

  final String text;
  final ParagraphKind kind;
  final int headingLevel; // 1 ~ 3，仅 heading 有效

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'text': text,
      'kind': kind.name,
      'level': headingLevel,
    };
  }

  /// 从 content.jsonl 的一行反序列化。
  ///
  /// 取值全部走容错路径：content.jsonl 是**逐行**读取的，
  /// 一行缺字段就抛异常会让**整章打不开**（历史文件、手改文件、
  /// 写到一半被杀的文件都会踩到）。缺字段时退化成普通段落，
  /// 而不是把异常抛给阅读器。
  static ParagraphBlock fromJson(Map<String, Object?> json) {
    final Object? rawText = json['text'];
    final Object? rawLevel = json['level'];
    final int level = rawLevel is num ? rawLevel.toInt() : 1;
    return ParagraphBlock(
      text: rawText is String ? rawText : '',
      kind: ParagraphKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => ParagraphKind.paragraph,
      ),
      headingLevel: level < 1 ? 1 : (level > 6 ? 6 : level),
    );
  }
}

/// 解析后的一个章节：标题 + 段落块列表。
class ParsedChapter {
  const ParsedChapter({required this.title, required this.blocks});

  final String title;
  final List<ParagraphBlock> blocks;
}

/// 解析后的一本书：元信息 + 全部章节。
class ParsedBook {
  const ParsedBook({
    required this.title,
    required this.author,
    required this.chapters,
  });

  final String title;
  final String author;
  final List<ParsedChapter> chapters;

  int get totalChars {
    int count = 0;
    for (ParsedChapter chapter in chapters) {
      for (ParagraphBlock block in chapter.blocks) {
        count += block.text.length;
      }
    }
    return count;
  }
}
