import 'package:sqflite/sqflite.dart';

/// app_state 表访问：设备号、同步端点等少量键值配置。
class AppStateDao {
  AppStateDao(this._db);

  final Database _db;

  Future<String?> get(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    await _db.insert(
      'app_state',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
