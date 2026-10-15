import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_reader/data/schema.dart';

/// 在主机上打开一个真 SQLite 库（桌面 ffi），跑的是生产同一份 schema 脚本。
///
/// 这样 DAO、迁移、源注册表、在线仓库都能脱离设备单测；
/// 否则这些层只能在真机上「读一遍代码猜它对不对」。
Future<Database> openTestDatabase({String? path}) async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    path ?? inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: kSchemaVersion,
      onCreate: (Database db, int version) => createSchema(db),
      onUpgrade: migrateSchema,
    ),
  );
}

/// 模拟真实的升级路径：先建 v1 老库并写入数据，再以新版本号打开触发 onUpgrade。
///
/// 用临时文件而不是内存库——内存库一关就没了，没法跨连接模拟升级。
Future<({Database database, String path})> openUpgradedDatabase() async {
  sqfliteFfiInit();
  final Directory dir = await Directory.systemTemp.createTemp('novel_reader_test');
  final String path = p.join(dir.path, 'legacy.db');

  final Database v1 = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (Database db, int version) => createV1Schema(db),
    ),
  );
  await v1.insert('books', <String, Object?>{
    'id': 'legacy-book',
    'title': '老库里的书',
    'author': '某人',
    'format': 'txt',
    'content_path': '/tmp/legacy.jsonl',
    'chapter_count': 3,
    'total_chars': 300,
    'file_size': 1024,
    'created_at': 1,
    'updated_at': 2,
  });
  await v1.close();

  final Database v2 = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: kSchemaVersion,
      onCreate: (Database db, int version) => createSchema(db),
      onUpgrade: migrateSchema,
    ),
  );
  return (database: v2, path: path);
}
