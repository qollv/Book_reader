import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/models/source_book.dart';

/// chapter_cache 表访问：在线章节正文的落盘缓存。
///
/// 这是「离线可读」的载体——上游把整本缓存做成 WorkManager 任务，
/// 读路径则「先本地后远程双发射」。这里只做存储，策略在仓库层。
class ChapterCacheDao {
  ChapterCacheDao(this._db);

  final Database _db;

  Future<SourceChapterContent?> find({
    required String sourceId,
    required String bookId,
    required String chapterId,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'chapter_cache',
      where: 'source_id = ? AND book_id = ? AND chapter_id = ?',
      whereArgs: <Object?>[sourceId, bookId, chapterId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _decode(rows.first);
  }

  Future<void> put({
    required String sourceId,
    required String bookId,
    required SourceChapterContent content,
  }) async {
    await _db.insert(
      'chapter_cache',
      <String, Object?>{
        'source_id': sourceId,
        'book_id': bookId,
        'chapter_id': content.id,
        'title': content.title,
        'content': _encode(content),
        'prev_id': content.prevId,
        'next_id': content.nextId,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 某书已缓存的章节 id 集合（判断「整本是否已缓存」用）。
  Future<Set<String>> cachedChapterIds(String sourceId, String bookId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'chapter_cache',
      columns: <String>['chapter_id'],
      where: 'source_id = ? AND book_id = ?',
      whereArgs: <Object?>[sourceId, bookId],
    );
    return <String>{for (final Map<String, Object?> r in rows) r['chapter_id'] as String};
  }

  Future<int> countByBook(String sourceId, String bookId) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM chapter_cache WHERE source_id = ? AND book_id = ?',
      <Object?>[sourceId, bookId],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<void> deleteByBook(String sourceId, String bookId) async {
    await _db.delete(
      'chapter_cache',
      where: 'source_id = ? AND book_id = ?',
      whereArgs: <Object?>[sourceId, bookId],
    );
  }

  Future<void> deleteBySource(String sourceId) async {
    await _db.delete('chapter_cache', where: 'source_id = ?', whereArgs: <Object?>[sourceId]);
  }

  /// 缓存占用字节数。
  ///
  /// 用 SQL 的 `length(cast(col as blob))` 在**不读内容**的前提下估算体积
  /// ——这个手法来自上游 `StorageStatsDao`，比把整表拉进内存再算省得多。
  Future<int> totalBytes() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT IFNULL(SUM(length(cast(content AS blob))), 0) AS bytes FROM chapter_cache',
    );
    return (rows.first['bytes'] as int?) ?? 0;
  }

  /// 按书聚合占用，供存储管理页展示与清理。
  Future<List<({String sourceId, String bookId, int bytes, int chapters})>> usageByBook() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT source_id, book_id, IFNULL(SUM(length(cast(content AS blob))), 0) AS bytes, '
      'COUNT(*) AS chapters FROM chapter_cache GROUP BY source_id, book_id ORDER BY bytes DESC',
    );
    return <({String sourceId, String bookId, int bytes, int chapters})>[
      for (final Map<String, Object?> r in rows)
        (
          sourceId: r['source_id'] as String,
          bookId: r['book_id'] as String,
          bytes: (r['bytes'] as int?) ?? 0,
          chapters: (r['chapters'] as int?) ?? 0,
        ),
    ];
  }

  /// 孤儿缓存：书已从 `books` 删除但缓存还在。存储审计用。
  Future<int> orphanCount() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM chapter_cache c '
      'WHERE NOT EXISTS (SELECT 1 FROM books b '
      'WHERE b.source_id = c.source_id AND b.source_book_id = c.book_id)',
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  String _encode(SourceChapterContent content) => jsonEncode(<String, Object?>{
        'blocks': <Map<String, Object?>>[
          for (final ParagraphBlock b in content.blocks) b.toJson(),
        ],
      });

  SourceChapterContent _decode(Map<String, Object?> row) {
    final List<ParagraphBlock> blocks = <ParagraphBlock>[];
    // 缓存内容坏了就当成没有段落，也不抛异常：
    // 上层会把它当成「缓存不可用」，转去走网络，而不是直接报错
    try {
      final Object? json = jsonDecode(row['content'] as String);
      if (json is Map && json['blocks'] is List) {
        for (final Object? b in json['blocks']! as List<Object?>) {
          if (b is Map) {
            final ParagraphBlock block = ParagraphBlock.fromJson(b.cast<String, Object?>());
            if (block.text.trim().isNotEmpty) {
              blocks.add(block);
            }
          }
        }
      }
    } on Object {
      blocks.clear();
    }
    return SourceChapterContent(
      id: row['chapter_id'] as String? ?? '',
      title: row['title'] as String? ?? '',
      blocks: blocks,
      prevId: row['prev_id'] as String?,
      nextId: row['next_id'] as String?,
    );
  }
}
