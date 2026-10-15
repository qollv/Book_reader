/// 章节：正文 content.jsonl 中的一段连续区间 [start, end)。
class Chapter {
  const Chapter({
    required this.bookId,
    required this.index,
    required this.title,
    required this.paragraphStart,
    required this.paragraphEnd,
  });

  final String bookId;
  final int index;
  final String title;
  final int paragraphStart; // 含
  final int paragraphEnd; // 不含

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'book_id': bookId,
      'chapter_index': index,
      'title': title,
      'paragraph_start': paragraphStart,
      'paragraph_end': paragraphEnd,
    };
  }

  static Chapter fromRow(Map<String, Object?> row) {
    // 容错读取：目录行残缺不该让整本书打不开
    return Chapter(
      bookId: row['book_id'] is String ? row['book_id']! as String : '',
      index: row['chapter_index'] is num ? (row['chapter_index']! as num).toInt() : 0,
      title: row['title'] is String ? row['title']! as String : '',
      paragraphStart:
          row['paragraph_start'] is num ? (row['paragraph_start']! as num).toInt() : 0,
      paragraphEnd: row['paragraph_end'] is num ? (row['paragraph_end']! as num).toInt() : 0,
    );
  }
}
