/// 笔记：划词选中正文后写的想法，锚点与书签一致。
class ReadingNote {
  const ReadingNote({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.lineIndex,
    required this.chapterTitle,
    required this.selectedText,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final int chapterIndex;
  final int paragraphIndex;
  final int lineIndex;
  final String chapterTitle;
  final String selectedText;
  final String content;
  final int createdAt;
  final int updatedAt;

  ReadingNote copyWith({required String content, required int updatedAt}) {
    return ReadingNote(
      id: id,
      bookId: bookId,
      chapterIndex: chapterIndex,
      paragraphIndex: paragraphIndex,
      lineIndex: lineIndex,
      chapterTitle: chapterTitle,
      selectedText: selectedText,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'paragraph_index': paragraphIndex,
      'line_index': lineIndex,
      'chapter_title': chapterTitle,
      'selected_text': selectedText,
      'content': content,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 对端同步数据/损坏库的字段类型不可信：is 判断 + 默认值，
  /// as T? 只防 null 不防类型错误（String 递给 num 字段会抛 TypeError）。
  static ReadingNote fromRow(Map<String, Object?> row) {
    return ReadingNote(
      id: row['id'] as String? ?? '',
      bookId: row['book_id'] as String? ?? '',
      chapterIndex: _intOf(row['chapter_index']),
      paragraphIndex: _intOf(row['paragraph_index']),
      lineIndex: _intOf(row['line_index']),
      chapterTitle: row['chapter_title'] as String? ?? '',
      selectedText: row['selected_text'] as String? ?? '',
      content: row['content'] as String? ?? '',
      createdAt: _intOf(row['created_at']),
      updatedAt: _intOf(row['updated_at']),
    );
  }

  static int _intOf(Object? value) => value is num ? value.toInt() : 0;
}
