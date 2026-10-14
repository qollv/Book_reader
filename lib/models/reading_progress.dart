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

  static ReadingProgress fromRow(Map<String, Object?> row) {
    return ReadingProgress(
      bookId: row['book_id'] as String? ?? '',
      chapterIndex: (row['chapter_index'] as num?)?.toInt() ?? 0,
      paragraphIndex: (row['paragraph_index'] as num?)?.toInt() ?? 0,
      lineIndex: (row['line_index'] as num?)?.toInt() ?? 0,
      // 对端设备可能写 int 而非 double，统一 toDouble
      percent: (row['percent'] as num?)?.toDouble() ?? 0,
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}
