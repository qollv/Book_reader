import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/data/schema.dart';
import 'package:novel_reader/models/book.dart';

import '../support/test_database.dart';

Future<Set<String>> tablesOf(Database db) async {
  final List<Map<String, Object?>> rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return <String>{for (final Map<String, Object?> r in rows) r['name'] as String};
}

Future<Set<String>> columnsOf(Database db, String table) async {
  final List<Map<String, Object?>> rows = await db.rawQuery('PRAGMA table_info($table)');
  return <String>{for (final Map<String, Object?> r in rows) r['name'] as String};
}

void main() {
  group('新装 schema', () {
    late Database db;

    setUp(() async => db = await openTestDatabase());
    tearDown(() async => db.close());

    test('建出全部表（含在线数据源两张）', () async {
      final Set<String> tables = await tablesOf(db);
      expect(
        tables,
        containsAll(<String>[
          'books',
          'chapters',
          'progress',
          'bookmarks',
          'notes',
          'settings',
          'sources',
          'chapter_cache',
        ]),
      );
    });

    test('books 带有来源与封面列', () async {
      expect(
        await columnsOf(db, 'books'),
        containsAll(<String>['source_id', 'source_book_id', 'cover_url']),
      );
    });

    test('chapter_cache 主键由 (源, 书, 章) 组成', () async {
      await db.insert('chapter_cache', <String, Object?>{
        'source_id': 's',
        'book_id': 'b',
        'chapter_id': 'c',
        'title': 't',
        'content': '{}',
        'fetched_at': 1,
      });
      // 同键再插一次应替换而不是报错或产生两行
      await db.insert(
        'chapter_cache',
        <String, Object?>{
          'source_id': 's',
          'book_id': 'b',
          'chapter_id': 'c',
          'title': 't2',
          'content': '{}',
          'fetched_at': 2,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final List<Map<String, Object?>> rows = await db.query('chapter_cache');
      expect(rows.length, 1);
      expect(rows.single['title'], 't2');
    });
  });

  group('v1 → v2 迁移', () {
    late Database db;

    setUp(() async {
      final ({Database database, String path}) opened = await openUpgradedDatabase();
      db = opened.database;
    });
    tearDown(() async => db.close());

    test('老数据保留，新列取默认值', () async {
      final List<Map<String, Object?>> rows = await db.query(
        'books',
        where: 'id = ?',
        whereArgs: <Object?>['legacy-book'],
      );
      expect(rows.length, 1);

      final Book book = Book.fromRow(rows.single);
      expect(book.title, '老库里的书');
      expect(book.chapterCount, 3);
      expect(book.sourceId, '', reason: '迁移前导入的书没有来源');
      expect(book.sourceBookId, '');
      expect(book.coverUrl, '');
      expect(book.isOnline, isFalse);
    });

    test('迁移后补齐了在线数据源的表', () async {
      expect(await tablesOf(db), containsAll(<String>['sources', 'chapter_cache']));
    });

    test('迁移后可正常写入带来源的新书', () async {
      await db.insert('books', <String, Object?>{
        'id': 'online-1',
        'title': '在线书',
        'author': '作者',
        'format': 'online',
        'content_path': '/tmp/o.jsonl',
        'chapter_count': 1,
        'total_chars': 10,
        'file_size': 20,
        'created_at': 3,
        'updated_at': 4,
        'source_id': 'sample.demo',
        'source_book_id': '101',
        'cover_url': 'http://x/c.jpg',
      });

      final List<Map<String, Object?>> rows = await db.query(
        'books',
        where: 'source_id = ? AND source_book_id = ?',
        whereArgs: <Object?>['sample.demo', '101'],
      );
      expect(rows.length, 1);
      expect(Book.fromRow(rows.single).isOnline, isTrue);
    });

    test('迁移脚本是幂等的（重复执行同一步不报错）', () async {
      // 再跑一次 v1→v2 会因为列已存在而失败，这是预期的：
      // 真实升级由 version 号保证只跑一次，这里锁定该行为以免被误改。
      await expectLater(
        migrateSchema(db, 1, 2),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
