/// txt 正文规范化。
///
/// 网上下载的 txt 常见两个问题：段落内被硬换行切断、行尾带一堆空格。
/// 这里按句读规则把续行并回段落：一行不以句末标点结尾，且下一行非空，
/// 就认为下一行是本段的延续；两侧都是拉丁字符时补一个空格，CJK 不补。
class TextNormalizer {
  // 出现这些字符视为段落自然结束（中英文 + 全角变体）
  static const String _sentenceEnders = '。！？…”」』；;.!?…';

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
        final String prev = buffer.last;
        buffer[buffer.length - 1] = prev + (_needsSpace(prev, trimmed) ? ' ' : '') + trimmed;
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

  /// 跨行拼接处的空格规则：
  /// - 两侧都是拉丁字符 → 补空格（避免 hello\nworld 粘成 helloworld）；
  /// - 一侧拉丁、一侧 CJK 表意文字 → 补空格（盘古之白）；
  /// - 两侧都是 CJK → 不补。
  static bool _needsSpace(String prev, String next) {
    if (prev.isEmpty || next.isEmpty) {
      return false;
    }
    final String prevLast = prev[prev.length - 1];
    final String nextFirst = next[0];
    if (_isLatin(prevLast) && _isLatin(nextFirst)) {
      return true;
    }
    return _isLatin(prevLast) && _isCjk(nextFirst);
  }

  static bool _isLatin(String char) {
    return RegExp(r'[A-Za-z0-9]').hasMatch(char);
  }

  static bool _isCjk(String char) {
    final int code = char.codeUnitAt(0);
    return code >= 0x4E00 && code <= 0x9FFF;
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
