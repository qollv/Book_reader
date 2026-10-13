import 'package:sqflite/sqflite.dart';

/// settings 表访问：单行存储 ReaderSettings 的 JSON 字符串。
class SettingsDao {
  SettingsDao(this._db);

  final Database _db;

  Future<String?> load() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'settings',
      where: 'id = 0',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['payload'] as String;
  }

  Future<void> save(String payload) async {
    await _db.insert(
      'settings',
      <String, Object?>{'id': 0, 'payload': payload},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
