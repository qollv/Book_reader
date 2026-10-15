/// 阅读进度。
///
/// 用「段落 + 行」做锚点而不是页码：字号行距变化后重新分页，
/// 锚点仍能定位到原来的阅读位置。
class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.lineIndex,
    required this.percent,
    required this.updatedAt,
  });

  final String bookId;
  final int chapterIndex;
  final int paragraphIndex; // 章内段落下标
  final int lineIndex; // 段内行下标
  final double percent; // 0.0 ~ 1.0
  final int updatedAt;

  ReadingProgress copyWith({double? percent, int? updatedAt}) {
    return ReadingProgress(
      bookId: bookId,
      chapterIndex: chapterIndex,
      paragraphIndex: paragraphIndex,
      lineIndex: lineIndex,
      percent: percent ?? this.percent,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'paragraph_index': paragraphIndex,
      'line_index': lineIndex,
      'percent': percent,
      'updated_at': updatedAt,
    };
  }

  /// 对端同步数据/损坏库的字段类型不可信：is 判断 + 默认值，
  /// as T? 只防 null 不防类型错误（String 递给 num 字段会抛 TypeError）。
  static ReadingProgress fromRow(Map<String, Object?> row) {
    return ReadingProgress(
      bookId: row['book_id'] as String? ?? '',
      chapterIndex: _intOf(row['chapter_index']),
      paragraphIndex: _intOf(row['paragraph_index']),
      lineIndex: _intOf(row['line_index']),
      // 对端设备可能写 int 而非 double，统一 toDouble
      percent: row['percent'] is num ? (row['percent'] as num).toDouble() : 0,
      updatedAt: _intOf(row['updated_at']),
    );
  }

  static int _intOf(Object? value) => value is num ? value.toInt() : 0;
}
