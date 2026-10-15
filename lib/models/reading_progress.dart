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
      bookId: _str(row['book_id']),
      chapterIndex: _int(row['chapter_index']),
      paragraphIndex: _int(row['paragraph_index']),
      lineIndex: _int(row['line_index']),
      // SQLite 里 REAL 列可能被存成整数（写入 0 而不是 0.0），
      // 直接 `as double` 会在这种情况下抛类型错误
      percent: _double(row['percent']).clamp(0.0, 1.0),
      updatedAt: _int(row['updated_at']),
    );
  }
}

String _str(Object? value) => value is String ? value : '';

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

double _double(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}
