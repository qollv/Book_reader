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
    };
  }

  static Bookmark fromRow(Map<String, Object?> row) {
    return Bookmark(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      chapterIndex: row['chapter_index'] as int,
      paragraphIndex: row['paragraph_index'] as int,
      lineIndex: row['line_index'] as int,
      chapterTitle: row['chapter_title'] as String,
      excerpt: row['excerpt'] as String,
      comment: row['comment'] as String,
      createdAt: row['created_at'] as int,
    );
  }
}
