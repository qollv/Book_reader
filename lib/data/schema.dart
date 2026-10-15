import 'package:sqflite/sqflite.dart';

/// 数据库版本与建表/迁移脚本。
///
/// 单独抽出来是为了让**迁移路径本身**可测：测试用 sqlite ffi 打开一个
/// 内存库，跑同一套 [createSchema] / [migrateSchema]，既能验证「新装」，
/// 也能验证「从 v1 升上来」。之前在 AppDatabase 里内联建表时，
/// 迁移脚本是唯一没被测试覆盖的代码，而那恰恰是最容易写错的地方。
///
/// 版本历史：
/// - v1：books / chapters / progress / bookmarks / notes / settings
/// - v2：在线数据源（sources / chapter_cache），books 增加来源与封面字段
const int kSchemaVersion = 2;

/// 建全套表（新装）。
Future<void> createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
      format TEXT NOT NULL,
      content_path TEXT NOT NULL,
      chapter_count INTEGER NOT NULL,
      total_chars INTEGER NOT NULL,
      file_size INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      source_id TEXT NOT NULL DEFAULT '',
      source_book_id TEXT NOT NULL DEFAULT '',
      cover_url TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.execute('''
    CREATE TABLE chapters (
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      title TEXT NOT NULL,
      paragraph_start INTEGER NOT NULL,
      paragraph_end INTEGER NOT NULL,
      PRIMARY KEY (book_id, chapter_index)
    )
  ''');
  await db.execute('''
    CREATE TABLE progress (
      book_id TEXT PRIMARY KEY,
      chapter_index INTEGER NOT NULL,
      paragraph_index INTEGER NOT NULL,
      line_index INTEGER NOT NULL,
      percent REAL NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
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
  await db.execute('''
    CREATE TABLE notes (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      paragraph_index INTEGER NOT NULL,
      line_index INTEGER NOT NULL,
      chapter_title TEXT NOT NULL,
      selected_text TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY CHECK (id = 0),
      payload TEXT NOT NULL
    )
  ''');
  await createOnlineSchema(db);
}

/// v1 的建表脚本，仅供迁移测试构造「老库」。
Future<void> createV1Schema(Database db) async {
  final Database v1 = db;
  await v1.execute('''
    CREATE TABLE books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
      format TEXT NOT NULL,
      content_path TEXT NOT NULL,
      chapter_count INTEGER NOT NULL,
      total_chars INTEGER NOT NULL,
      file_size INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await v1.execute('''
    CREATE TABLE chapters (
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      title TEXT NOT NULL,
      paragraph_start INTEGER NOT NULL,
      paragraph_end INTEGER NOT NULL,
      PRIMARY KEY (book_id, chapter_index)
    )
  ''');
  await v1.execute('''
    CREATE TABLE progress (
      book_id TEXT PRIMARY KEY,
      chapter_index INTEGER NOT NULL,
      paragraph_index INTEGER NOT NULL,
      line_index INTEGER NOT NULL,
      percent REAL NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await v1.execute('''
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
  await v1.execute('''
    CREATE TABLE notes (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL,
      paragraph_index INTEGER NOT NULL,
      line_index INTEGER NOT NULL,
      chapter_title TEXT NOT NULL,
      selected_text TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await v1.execute('''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY CHECK (id = 0),
      payload TEXT NOT NULL
    )
  ''');
}

/// 在线数据源相关表（v2 新增）。
Future<void> createOnlineSchema(Database db) async {
  await db.execute('''
    CREATE TABLE sources (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      manifest TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      installed_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      last_error TEXT NOT NULL DEFAULT '',
      origin TEXT NOT NULL DEFAULT 'builtin'
    )
  ''');
  await db.execute('''
    CREATE TABLE chapter_cache (
      source_id TEXT NOT NULL,
      book_id TEXT NOT NULL,
      chapter_id TEXT NOT NULL,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      prev_id TEXT,
      next_id TEXT,
      fetched_at INTEGER NOT NULL,
      PRIMARY KEY (source_id, book_id, chapter_id)
    )
  ''');
  await db.execute('CREATE INDEX idx_chapter_cache_book ON chapter_cache(source_id, book_id)');
  await db.execute('CREATE INDEX idx_books_source ON books(source_id, source_book_id)');
}

/// 逐版本迁移。每个分支只做「上一版 → 下一版」的一步，便于叠加与单独测试。
Future<void> migrateSchema(Database db, int from, int to) async {
  if (from < 2) {
    // 给已有行补列：本地导入的书表现为「无来源」
    await db.execute("ALTER TABLE books ADD COLUMN source_id TEXT NOT NULL DEFAULT ''");
    await db.execute("ALTER TABLE books ADD COLUMN source_book_id TEXT NOT NULL DEFAULT ''");
    await db.execute("ALTER TABLE books ADD COLUMN cover_url TEXT NOT NULL DEFAULT ''");
    await createOnlineSchema(db);
  }
}
