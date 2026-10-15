import 'dart:async';
import 'dart:convert';

import 'package:novel_reader/core/source/json_rule_engine.dart';
import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/data/dao/source_dao.dart';
import 'package:novel_reader/models/source_manifest.dart';
import 'package:novel_reader/services/source/cached_http.dart';
import 'package:novel_reader/services/source/http_fetcher.dart';
import 'package:novel_reader/services/source/text_decoder.dart';

/// 一个源在宿主里的运行状态。
enum SourceStatus {
  /// 已加载、可用。
  ready,

  /// 用户关掉了。
  disabled,

  /// apiVersion 与宿主不兼容（跨组）。
  incompatible,

  /// 声明损坏或加载失败。
  error,
}

/// 源列表里的一项：声明 + 运行状态 + 可用引擎。
class SourceEntry {
  const SourceEntry({
    required this.record,
    required this.status,
    this.manifest,
    this.engine,
    this.error = '',
  });

  final SourceRecord record;
  final SourceStatus status;
  final SourceManifest? manifest;
  final SourceEngine? engine;
  final String error;

  String get id => record.id;

  String get name => manifest?.name ?? record.name;

  bool get usable => status == SourceStatus.ready && engine != null;
}

/// 安装结果：成功与否 + 可直接展示给用户的原因。
class SourceInstallResult {
  const SourceInstallResult({required this.ok, required this.message, this.sourceId});

  final bool ok;
  final String message;
  final String? sourceId;
}

/// 源注册表：装载声明、门控兼容性、维护启用状态、生成引擎。
///
/// 对照上游 `PluginManager`：它要处理 APK 解析、`PathClassLoader` 加载、
/// 反射注入、assets/libs 解包、广播发现 App 插件……这里全部塌缩成
/// 「一行 DB 记录 + 一个 JSON 声明 + 一个引擎实例」，但保留了三个真正
/// 有价值的部分：**兼容性门控、版本防降级、错误留痕**。
class SourceRegistry {
  SourceRegistry({
    required SourceDao dao,
    required HttpFetcher fetcher,
    int hostApiVersion = kHostSourceApiVersion,
  })  : _dao = dao,
        _fetcher = fetcher,
        _hostApiVersion = hostApiVersion;

  final SourceDao _dao;
  final HttpFetcher _fetcher;
  final int _hostApiVersion;

  final Map<String, SourceEngine> _engines = <String, SourceEngine>{};
  final List<SourceEntry> _entries = <SourceEntry>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<SourceEntry> get entries => List<SourceEntry>.unmodifiable(_entries);

  Stream<void> get changes => _changes.stream;

  /// 可用（ready）的源。
  List<SourceEntry> get usableEntries =>
      _entries.where((SourceEntry e) => e.usable).toList(growable: false);

  SourceEntry? entryOf(String id) =>
      _entries.where((SourceEntry e) => e.id == id).firstOrNull;

  SourceEngine? engineFor(String id) => _engines[id];

  /// 从库里重放全部源并重建引擎。
  Future<void> load() async {
    _engines.clear();
    _entries.clear();
    final List<SourceRecord> records = await _dao.findAll();
    for (final SourceRecord record in records) {
      _entries.add(_buildEntry(record));
    }
    _notify();
  }

  SourceEntry _buildEntry(SourceRecord record) {
    final SourceManifest manifest;
    try {
      manifest = record.parseManifest();
    } on Object catch (e) {
      return SourceEntry(
        record: record,
        status: SourceStatus.error,
        error: '声明解析失败: $e',
      );
    }

    if (!isSourceApiSupported(manifest.apiVersion, _hostApiVersion)) {
      return SourceEntry(
        record: record,
        status: SourceStatus.incompatible,
        manifest: manifest,
        error: '数据源 API ${manifest.apiVersion} 与本版本不兼容'
            '（宿主支持 API $_hostApiVersion）',
      );
    }

    if (!record.enabled) {
      return SourceEntry(
        record: record,
        status: SourceStatus.disabled,
        manifest: manifest,
        error: record.lastError,
      );
    }

    final SourceEngine engine = _createEngine(manifest);
    _engines[manifest.id] = engine;
    return SourceEntry(
      record: record,
      status: SourceStatus.ready,
      manifest: manifest,
      engine: engine,
      error: record.lastError,
    );
  }

  SourceEngine _createEngine(SourceManifest manifest) {
    return JsonRuleEngine(
      manifest: manifest,
      http: CachedHttp(
        fetcher: _fetcher,
        defaultTtl: Duration(milliseconds: manifest.cacheTtlMs),
        maxEntries: manifest.cacheMaxEntries,
        permits: manifest.permits,
      ),
    );
  }

  /// 安装/更新一个源。
  ///
  /// 「原子性」在这里的含义不是解包事务，而是**先校验后落库**：
  /// 新声明只要有一处不合法就完全不动库里已有的那一行，
  /// 于是失败的更新不会把用户的可用源弄坏。
  Future<SourceInstallResult> install(
    String manifestJson, {
    SourceOrigin origin = SourceOrigin.file,
    bool replace = true,
  }) async {
    final SourceManifest manifest;
    try {
      final Object? json = jsonDecode(manifestJson);
      if (json is! Map) {
        return const SourceInstallResult(ok: false, message: 'manifest 不是 JSON 对象');
      }
      manifest = SourceManifest.fromJson(json.cast<String, Object?>());
    } on SourceManifestException catch (e) {
      return SourceInstallResult(ok: false, message: e.message);
    } on FormatException catch (e) {
      return SourceInstallResult(ok: false, message: 'JSON 语法错误: ${e.message}');
    }

    if (!isSourceApiSupported(manifest.apiVersion, _hostApiVersion)) {
      return SourceInstallResult(
        ok: false,
        message: '数据源 API 版本 ${manifest.apiVersion} 不被支持（宿主 API $_hostApiVersion）',
      );
    }
    if (!isKnownCharset(manifest.charset)) {
      return SourceInstallResult(
        ok: false,
        message: '不支持的编码: ${manifest.charset}',
      );
    }

    final SourceRecord? existing = await _dao.findById(manifest.id);
    if (existing != null) {
      if (!replace) {
        return SourceInstallResult(ok: false, message: '源 ${manifest.id} 已存在', sourceId: manifest.id);
      }
      // 防降级：上游靠 version 比较挡住「商店回滚」，这里同样保留
      final int currentVersion = _versionCodeOf(existing);
      if (currentVersion > manifest.versionCode) {
        return SourceInstallResult(
          ok: false,
          message: '已安装版本更高（$currentVersion > ${manifest.versionCode}），'
              '如需强制降级请先卸载',
          sourceId: manifest.id,
        );
      }
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    await _dao.upsert(SourceRecord(
      id: manifest.id,
      name: manifest.name,
      manifestJson: manifestJson,
      enabled: existing?.enabled ?? true,
      installedAt: existing?.installedAt ?? now,
      updatedAt: now,
      lastError: '',
      origin: origin,
    ));
    await load();
    return SourceInstallResult(
      ok: true,
      message: existing == null ? '已安装：${manifest.name}' : '已更新：${manifest.name}',
      sourceId: manifest.id,
    );
  }

  int _versionCodeOf(SourceRecord record) {
    try {
      return record.parseManifest().versionCode;
    } on Object {
      return 0;
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _dao.setEnabled(id, enabled);
    await load();
  }

  Future<void> remove(String id) async {
    await _dao.delete(id);
    _engines.remove(id);
    await load();
  }

  /// 记录运行期错误（对应上游把加载失败原因写进插件目录的 `error` 文件）。
  Future<void> markError(String id, String error) async {
    await _dao.setLastError(id, error);
    final int index = _entries.indexWhere((SourceEntry e) => e.id == id);
    if (index >= 0) {
      final SourceEntry old = _entries[index];
      _entries[index] = SourceEntry(
        record: old.record,
        status: SourceStatus.error,
        manifest: old.manifest,
        engine: old.engine,
        error: error,
      );
      _notify();
    }
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
