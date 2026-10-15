/// 书架中的一本书。
///
/// 正文不存数据库：导入时规范化为 content.jsonl（一段一行），
/// 章节只记录该章节覆盖的段落区间，阅读时按需加载。
///
/// 在线来源的书同样落成 content.jsonl（缓存整本时），因此阅读链路
/// 对「本地导入」与「在线导入」完全一致；`sourceId` 只用于回源更新与去重。
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
    this.sourceId = '',
    this.sourceBookId = '',
    this.coverUrl = '',
  });

  final String id;
  final String title;
  final String author;
  final String format; // txt / md / docx / online
  final String contentPath; // content.jsonl 绝对路径
  final int chapterCount;
  final int totalChars;
  final int fileSize;
  final int createdAt; // 毫秒时间戳
  final int updatedAt;

  /// 在线来源的源 id；本地导入为空串。
  final String sourceId;

  /// 在线来源里这本书的 id（源的 bookId）；本地导入为空串。
  final String sourceBookId;

  /// 封面地址；本地导入为空串。
  final String coverUrl;

  bool get isOnline => sourceId.isNotEmpty;

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
      'source_id': sourceId,
      'source_book_id': sourceBookId,
      'cover_url': coverUrl,
    };
  }

  static Book fromRow(Map<String, Object?> row) {
    // 容错读取：库里一行残缺（旧版本 schema、被外部改动、写入中断）
    // 不应该让整个书架打不开。缺字段退化成空串/0。
    return Book(
      id: _string(row['id']),
      title: _string(row['title']),
      author: _string(row['author']),
      format: _string(row['format']),
      contentPath: _string(row['content_path']),
      chapterCount: _integer(row['chapter_count']),
      totalChars: _integer(row['total_chars']),
      fileSize: _integer(row['file_size']),
      createdAt: _integer(row['created_at']),
      updatedAt: _integer(row['updated_at']),
      // 迁移前的旧行没有这三列的值（DEFAULT ''）
      sourceId: _string(row['source_id']),
      sourceBookId: _string(row['source_book_id']),
      coverUrl: _string(row['cover_url']),
    );
  }
}

String _string(Object? value) => value is String ? value : '';

int _integer(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}
