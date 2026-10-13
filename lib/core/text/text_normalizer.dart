/// txt 正文规范化。
///
/// 网上下载的 txt 常见两个问题：段落内被硬换行切断、行尾带一堆空格。
/// 这里按中文句读规则把续行并回段落：一行不以句末标点结尾，且下一行非空，
/// 就认为下一行是本段的延续，直接拼接（不补空格）。
class TextNormalizer {
  // 出现这些字符视为段落自然结束
  static const String _sentenceEnders = '。！？…”」』！？；;';

  /// 把原始 txt 规范化为段落列表，空段被丢弃。
  static List<String> reflow(String raw) {
    final List<String> paragraphs = <String>[];
    final List<String> buffer = <String>[];

    for (String line in raw.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        _flush(buffer, paragraphs);
        continue;
      }
      if (buffer.isNotEmpty && !_endsSentence(buffer.last)) {
        buffer[buffer.length - 1] = buffer.last + trimmed;
      } else {
        buffer.add(trimmed);
      }
    }
    _flush(buffer, paragraphs);
    return paragraphs;
  }

  static bool _endsSentence(String line) {
    if (line.isEmpty) {
      return false;
    }
    return _sentenceEnders.contains(line[line.length - 1]);
  }

  static void _flush(List<String> buffer, List<String> paragraphs) {
    for (String text in buffer) {
      if (text.isNotEmpty) {
        paragraphs.add(text);
      }
    }
    buffer.clear();
  }
}
