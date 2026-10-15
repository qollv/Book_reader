import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// TC-20：DEF-03 配套 schema 迁移。bookmarks 表 v1→v2 增加 updated_at，
// ALTER 必须保留旧行数据（用户书签无价），默认值 0 表示从未更新。
void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;

  test('v1 → v2 迁移：updated_at 列补齐且旧书签数据保留', () async {
    final Database db = await factory.openDatabase(inMemoryDatabasePath);
    try {
      // 手工建 v1 旧 schema（无 updated_at）
      await db.execute('''
        CREATE TABLE bookmarks (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL,
          chapter_index INTEGER NOT NULL,
          paragraph_index INTEGER NOT NULL,
          line_index INTEGER NOT NULL,
          chapter_title TEXT NOT NULL,
          excerpt TEXT NOT NULL,
          comment TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.insert('bookmarks', <String, Object?>{
        'id': 'bm-old',
        'book_id': 'book-1',
        'chapter_index': 1,
        'paragraph_index': 2,
        'line_index': 0,
        'chapter_title': '第一章',
        'excerpt': '旧摘录',
        'comment': '旧短评',
        'created_at': 1000,
      });

      await AppDatabase.migrateV1ToV2(db);

      final List<Map<String, Object?>> columns =
          await db.rawQuery('PRAGMA table_info(bookmarks)');
      expect(
        columns.map((Map<String, Object?> c) => c['name']),
        contains('updated_at'),
      );

      final List<Map<String, Object?>> rows = await db.query('bookmarks');
      expect(rows.length, 1);
      expect(rows.first['comment'], '旧短评', reason: '迁移不得丢失旧书签');
      expect(rows.first['updated_at'], 0, reason: '旧书签默认从未更新');
    } finally {
      await db.close();
    }
  });

  test('重复迁移同一库会抛错（sqflite 按版本号只跑一次，此处验证 DDL 非幂等）', () async {
    final Database db = await factory.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute('''
        CREATE TABLE bookmarks (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL,
          chapter_index INTEGER NOT NULL,
          paragraph_index INTEGER NOT NULL,
          line_index INTEGER NOT NULL,
          chapter_title TEXT NOT NULL,
          excerpt TEXT NOT NULL,
          comment TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL DEFAULT 0
        )
      ''');
      // 已含新列时重复 ADD COLUMN 必须失败——证明迁移只应执行一次
      expect(() => AppDatabase.migrateV1ToV2(db), throwsA(isA<DatabaseException>()));
    } finally {
      await db.close();
    }
  });
}
