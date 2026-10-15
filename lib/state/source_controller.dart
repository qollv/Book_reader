import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:novel_reader/data/dao/source_dao.dart';
import 'package:novel_reader/models/source_manifest.dart';
import 'package:novel_reader/services/source/source_registry.dart';

/// 数据源管理状态：装载、启停、安装、卸载、激活源选择。
class SourceController extends ChangeNotifier {
  SourceController({required SourceRegistry registry}) : _registry = registry;

  final SourceRegistry _registry;

  /// 随包的示例源路径。它同时是文档：想写自己的源，照抄这份就行。
  static const String sampleSourceAsset = 'assets/sources/sample_source.json';

  List<SourceEntry> _entries = <SourceEntry>[];
  String? _activeSourceId;
  bool _loading = true;

  List<SourceEntry> get entries => _entries;

  List<SourceEntry> get usableEntries =>
      _entries.where((SourceEntry e) => e.usable).toList(growable: false);

  bool get isLoading => _loading;

  /// 当前激活的源。没有可用源时为 null，UI 据此显示引导而不是空列表。
  String? get activeSourceId => _activeSourceId;

  SourceEntry? get activeEntry =>
      _activeSourceId == null ? null : _registry.entryOf(_activeSourceId!);

  bool get hasUsableSource => usableEntries.isNotEmpty;

  @override
  void dispose() {
    _registry.changes.drain<void>().ignore();
    super.dispose();
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    await _registry.load();
    _entries = _registry.entries;

    // 激活源失效时（被停用/卸载/不兼容）自动落到第一个可用源，
    // 避免 UI 一直指着一条已经不存在的源
    if (_activeSourceId == null || _registry.engineFor(_activeSourceId!) == null) {
      _activeSourceId = usableEntries.isEmpty ? null : usableEntries.first.id;
    }
    _loading = false;
    notifyListeners();
  }

  void setActiveSource(String sourceId) {
    if (_activeSourceId == sourceId) {
      return;
    }
    _activeSourceId = sourceId;
    notifyListeners();
  }

  Future<void> setEnabled(String sourceId, bool enabled) async {
    await _registry.setEnabled(sourceId, enabled);
    await load();
  }

  Future<void> remove(String sourceId) async {
    await _registry.remove(sourceId);
    if (_activeSourceId == sourceId) {
      _activeSourceId = null;
    }
    await load();
  }

  /// 安装一份声明文本（用户粘贴、从文件读取、或内置示例都走这里）。
  Future<SourceInstallResult> install(
    String manifestJson, {
    SourceOrigin origin = SourceOrigin.file,
  }) async {
    final SourceInstallResult result =
        await _registry.install(manifestJson, origin: origin);
    await load();
    return result;
  }

  /// 安装随包示例源。
  Future<SourceInstallResult> installSample() async {
    final String raw = await rootBundle.loadString(sampleSourceAsset);
    return install(raw, origin: SourceOrigin.builtin);
  }

  /// 从本地文件安装（.json 源声明）。
  Future<SourceInstallResult> installFromFile(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      return const SourceInstallResult(ok: false, message: '文件不存在');
    }
    final String text = await file.readAsString();
    return install(text, origin: SourceOrigin.file);
  }

  /// 导出某条源的声明原文，便于分享与排查。
  String exportManifest(String sourceId) {
    final SourceEntry? entry = _registry.entryOf(sourceId);
    if (entry == null) {
      return '';
    }
    try {
      final Map<String, Object?> json =
          (jsonDecode(entry.record.manifestJson) as Map).cast<String, Object?>();
      return const JsonEncoder.withIndent('  ').convert(json);
    } on Object {
      return entry.record.manifestJson;
    }
  }

  /// 源状态的人类可读描述。
  static String describeStatus(SourceStatus status) {
    return switch (status) {
      SourceStatus.ready => '可用',
      SourceStatus.disabled => '已停用',
      SourceStatus.incompatible => '版本不兼容',
      SourceStatus.error => '加载失败',
    };
  }

  /// 源能力的人类可读列表。
  static String describeCapabilities(SourceManifest? manifest) {
    if (manifest == null) {
      return '';
    }
    const Map<SourceCapability, String> names = <SourceCapability, String>{
      SourceCapability.search: '搜索',
      SourceCapability.explore: '探索',
      SourceCapability.bookInfo: '详情',
      SourceCapability.volumes: '目录',
      SourceCapability.chapter: '正文',
    };
    return manifest.capabilities.map((SourceCapability c) => names[c] ?? c.name).join(' · ');
  }
}
