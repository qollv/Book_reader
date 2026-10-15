import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/models/source_manifest.dart';

/// sources 表的一行：源声明 + 启用状态 + 安装元信息。
class SourceRecord {
  const SourceRecord({
    required this.id,
    required this.name,
    required this.manifestJson,
    required this.installedAt,
    required this.updatedAt,
    this.enabled = true,
    this.lastError = '',
    this.origin = SourceOrigin.builtin,
  });

  final String id;
  final String name;

  /// 原始 manifest JSON 文本（保留原样，便于带注释/未知字段往返）。
  final String manifestJson;

  final bool enabled;
  final int installedAt;
  final int updatedAt;

  /// 最近一次加载/运行错误；空串表示正常。
  final String lastError;

  final SourceOrigin origin;

  /// 解析回 manifest。声明被外部破坏时抛 [SourceManifestException]。
  SourceManifest parseManifest() {
    final Object? json = jsonDecode(manifestJson);
    if (json is! Map) {
      throw const SourceManifestException('manifest 不是 JSON 对象');
    }
    return SourceManifest.fromJson(json.cast<String, Object?>());
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'name': name,
        'manifest': manifestJson,
        'enabled': enabled ? 1 : 0,
        'installed_at': installedAt,
        'updated_at': updatedAt,
        'last_error': lastError,
        'origin': origin.name,
      };

  static SourceRecord fromRow(Map<String, Object?> row) {
    return SourceRecord(
      id: row['id'] as String,
      name: row['name'] as String,
      manifestJson: row['manifest'] as String,
      enabled: (row['enabled'] as int? ?? 1) == 1,
      installedAt: row['installed_at'] as int? ?? 0,
      updatedAt: row['updated_at'] as int? ?? 0,
      lastError: (row['last_error'] as String?) ?? '',
      origin: SourceOrigin.values.firstWhere(
        (SourceOrigin o) => o.name == row['origin'],
        orElse: () => SourceOrigin.builtin,
      ),
    );
  }
}

/// 源的来源渠道：内置 / 用户导入文件 / 远程商店。
enum SourceOrigin { builtin, file, store }

/// sources 表访问。
class SourceDao {
  SourceDao(this._db);

  final Database _db;

  Future<void> upsert(SourceRecord record) async {
    await _db.insert('sources', record.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db.delete('sources', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<List<SourceRecord>> findAll() async {
    final List<Map<String, Object?>> rows =
        await _db.query('sources', orderBy: 'installed_at ASC');
    return rows.map(SourceRecord.fromRow).toList();
  }

  Future<SourceRecord?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'sources',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : SourceRecord.fromRow(rows.first);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _db.update(
      'sources',
      <String, Object?>{'enabled': enabled ? 1 : 0, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setLastError(String id, String error) async {
    await _db.update(
      'sources',
      <String, Object?>{'last_error': error, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
