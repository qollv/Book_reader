import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 应用数据库（单例）。
///
/// 表结构只在 onCreate 创建，后续版本演进走 onUpgrade，
/// 不破坏用户已有数据。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _dbName = 'novel_reader.db';
  static const int _dbVersion = 1;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    final String dir = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
      onDowngrade: _onDowngrade,
    );
    return _database!;
  }

  /// 版本升级迁移：按顺序执行 DDL，绝不回滚式重建（用户数据无价）。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2 示例（实际有迁移时取消注释并补 DDL）：
    // if (oldVersion < 2) { await db.execute('ALTER TABLE books ADD COLUMN cover_path TEXT'); }
  }

  /// 降级（装回旧版 App）：保留数据，由旧版本代码自行兼容。
  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) async {
    // 暂不做任何操作：旧代码读不到新列时会忽略它们
  }

  Future<void> _createTables(Database db, int version) async {
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
        updated_at INTEGER NOT NULL
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
    await db.execute('''
      CREATE TABLE app_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }
}
