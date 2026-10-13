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
    );
    return _database!;
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
  }
}
