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

  static ReadingNote fromRow(Map<String, Object?> row) {
    return ReadingNote(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      chapterIndex: row['chapter_index'] as int,
      paragraphIndex: row['paragraph_index'] as int,
      lineIndex: row['line_index'] as int,
      chapterTitle: row['chapter_title'] as String,
      selectedText: row['selected_text'] as String,
      content: row['content'] as String,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }
}
