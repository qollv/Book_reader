import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/data/schema.dart';

/// 应用数据库（单例）。
///
/// 建表与迁移脚本在 [schema.dart] 里，测试可以对同一份脚本跑
/// 「新装」与「v1 升级」两条路径，避免迁移脚本成为唯一没被测过的代码。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _dbName = 'novel_reader.db';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    final String dir = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dir, _dbName),
      version: kSchemaVersion,
      onCreate: (Database db, int version) => createSchema(db),
      onUpgrade: migrateSchema,
    );
    return _database!;
  }
}
