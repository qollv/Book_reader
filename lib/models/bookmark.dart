/// 书签：锚定到某一章某一段的某一行，可附带短评。
class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.lineIndex,
    required this.chapterTitle,
    required this.excerpt,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final int chapterIndex;
  final int paragraphIndex;
  final int lineIndex;
  final String chapterTitle;
  final String excerpt; // 锚点所在行的原文
  final String comment;
  final int createdAt;
  final int updatedAt; // 与笔记对齐，供同步合并按 last-write-wins 取较新者

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'paragraph_index': paragraphIndex,
      'line_index': lineIndex,
      'chapter_title': chapterTitle,
      'excerpt': excerpt,
      'comment': comment,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 对端同步数据/损坏库的字段类型不可信：is 判断 + 默认值，
  /// as T? 只防 null 不防类型错误（String 递给 num 字段会抛 TypeError）。
  static Bookmark fromRow(Map<String, Object?> row) {
    return Bookmark(
      id: row['id'] as String? ?? '',
      bookId: row['book_id'] as String? ?? '',
      chapterIndex: _intOf(row['chapter_index']),
      paragraphIndex: _intOf(row['paragraph_index']),
      lineIndex: _intOf(row['line_index']),
      chapterTitle: row['chapter_title'] as String? ?? '',
      excerpt: row['excerpt'] as String? ?? '',
      comment: row['comment'] as String? ?? '',
      createdAt: _intOf(row['created_at']),
      updatedAt: _intOf(row['updated_at']),
    );
  }

  static int _intOf(Object? value) => value is num ? value.toInt() : 0;
}
