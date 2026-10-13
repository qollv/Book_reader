/// 书架中的一本书。
///
/// 正文不存数据库：导入时规范化为 content.jsonl（一段一行），
/// 章节只记录该章节覆盖的段落区间，阅读时按需加载。
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.contentPath,
    required this.chapterCount,
    required this.totalChars,
    required this.fileSize,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String author;
  final String format; // txt / md / docx
  final String contentPath; // content.jsonl 绝对路径
  final int chapterCount;
  final int totalChars;
  final int fileSize;
  final int createdAt; // 毫秒时间戳
  final int updatedAt;

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'author': author,
      'format': format,
      'content_path': contentPath,
      'chapter_count': chapterCount,
      'total_chars': totalChars,
      'file_size': fileSize,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  static Book fromRow(Map<String, Object?> row) {
    return Book(
      id: row['id'] as String,
      title: row['title'] as String,
      author: row['author'] as String,
      format: row['format'] as String,
      contentPath: row['content_path'] as String,
      chapterCount: row['chapter_count'] as int,
      totalChars: row['total_chars'] as int,
      fileSize: row['file_size'] as int,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }
}
