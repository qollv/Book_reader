/// 在线数据源的声明式描述（manifest.json）。
///
/// 设计取向：可扩展的接口 + 声明式实现，取代上游 LightNovelReader 的
/// 「一个数据源 = 一个 APK 插件 + 反射注入」（Dart AOT 无法动态加载类）。
///
/// 兼容性沿用上游 ApiCompat 的**硬分组**语义：跨组完全不兼容，
/// 组内只允许 `sourceApi <= hostApi`。分组表是发布期维护的常量，
/// 加新组意味着老源整体失效——这是刻意的取舍，避免无限向后兼容。
library;

/// 宿主支持的数据源 API 版本。
const int kHostSourceApiVersion = 4;

/// ApiCompat 分组表：同一组内互相兼容，跨组一律不兼容。
const List<Set<int>> kSourceApiGroups = <Set<int>>[
  <int>{1},
  <int>{2, 3},
  <int>{4},
];

/// 源的 API 版本是否被宿主接受。
bool isSourceApiSupported(int sourceApi, int hostApi) {
  final int hostGroup = kSourceApiGroups.indexWhere((Set<int> g) => g.contains(hostApi));
  final int sourceGroup = kSourceApiGroups.indexWhere((Set<int> g) => g.contains(sourceApi));
  if (hostGroup < 0 || sourceGroup < 0) {
    return false;
  }
  return hostGroup == sourceGroup && sourceApi <= hostApi;
}

/// 源声明不合法时的可读错误。UI 直接展示，不抛原始异常。
class SourceManifestException implements Exception {
  const SourceManifestException(this.message);

  final String message;

  @override
  String toString() => 'SourceManifestException: $message';
}

/// 源能力。UI 据此显示/隐藏入口，而不是等用户点进去才报错。
enum SourceCapability { search, explore, bookInfo, volumes, chapter }

/// 过滤器的取值形态。
enum SourceFilterType { single, slider, toggle }

/// 排序/筛选过滤器：把 UI 选择映射成附加请求参数。
class SourceFilterRule {
  const SourceFilterRule({
    required this.key,
    required this.title,
    required this.type,
    this.choices = const <String, String>{},
    this.defaultChoice = '',
    this.min = 0,
    this.max = 100,
    this.steps = 10,
    this.defaultValue = 0,
    this.extraPrefix = '&',
  });

  final String key;
  final String title;
  final SourceFilterType type;

  /// single 型：显示名 → 附加参数（原样拼进 URL，不要 URL 编码）。
  final Map<String, String> choices;
  final String defaultChoice;

  /// slider 型取值区间。
  final double min;
  final double max;
  final int steps;
  final double defaultValue;

  /// 拼参数的连接符，默认 `&`；URL 里还没有 query 时可设为 `?`。
  final String extraPrefix;

  /// 把当前选择展开成 URL 附加片段。
  String expand({required String choice, required double slider, required bool toggle}) {
    return switch (type) {
      SourceFilterType.single => choices[choice] ?? '',
      SourceFilterType.slider =>
        '$extraPrefix$key=${slider.round()}',
      SourceFilterType.toggle => toggle ? '$extraPrefix$key=1' : '',
    };
  }

  static SourceFilterRule fromJson(Map<String, Object?> json) {
    final String key = _str(json['key'], field: 'filter.key');
    final String type = _str(json['type'], field: 'filter.type');
    final String title = (json['title'] as String?) ?? key;
    switch (type) {
      case 'single':
        final Object? raw = json['choices'];
        if (raw is! Map) {
          throw const SourceManifestException('single 过滤器缺少 choices');
        }
        return SourceFilterRule(
          key: key,
          title: title,
          type: SourceFilterType.single,
          choices: <String, String>{
            for (final MapEntry<Object?, Object?> e in raw.entries)
              e.key.toString(): e.value?.toString() ?? '',
          },
          defaultChoice: (json['default'] as String?) ?? '',
        );
      case 'slider':
        return SourceFilterRule(
          key: key,
          title: title,
          type: SourceFilterType.slider,
          min: _num(json['min'], 0),
          max: _num(json['max'], 100),
          steps: (json['steps'] as num?)?.toInt() ?? 10,
          defaultValue: _num(json['default'], 0),
        );
      case 'toggle':
        return SourceFilterRule(
          key: key,
          title: title,
          type: SourceFilterType.toggle,
          defaultChoice: (json['default'] == true).toString(),
        );
      default:
        throw SourceManifestException('未知过滤器类型: $type');
    }
  }
}

/// 搜索入口（一个源可以有多种搜索方式，如按书名/按作者）。
class SourceSearchTypeRule {
  const SourceSearchTypeRule({required this.id, required this.name, required this.path});

  final String id;
  final String name;
  final String path;

  static SourceSearchTypeRule fromJson(Map<String, Object?> json) {
    return SourceSearchTypeRule(
      id: _str(json['id'], field: 'search.type.id'),
      name: (json['name'] as String?) ?? _str(json['id'], field: 'search.type.id'),
      path: _str(json['path'], field: 'search.type.path'),
    );
  }
}

/// 搜索/探索列表页的解析规则。
///
/// 注意 [path] 对**探索页必填**，对搜索页可以为空——搜索的 URL 属于
/// 每个 `type`（按书名搜/按作者搜的地址不同），列表规则只描述怎么解析。
class SourceListRule {
  const SourceListRule({
    this.path = '',
    required this.listSelector,
    this.fields = const <String, String>{},
    this.paging = SourcePagingRule.none,
    this.filters = const <SourceFilterRule>[],
  });

  final String path;

  /// 列表项选择器；为空表示整页就是一个条目（搜索直跳详情）。
  final String listSelector;

  /// 字段名 → 字段提取规格（见 FieldSpec）。约定字段：title/id/author/cover/description/tags。
  final Map<String, String> fields;

  final SourcePagingRule paging;
  final List<SourceFilterRule> filters;

  static SourceListRule fromJson(
    Map<String, Object?> json, {
    required String where,
    bool requirePath = false,
  }) {
    final Object? rawPath = json['path'];
    if (requirePath && (rawPath is! String || rawPath.isEmpty)) {
      throw SourceManifestException('缺少必填字段 $where.path');
    }
    return SourceListRule(
      path: rawPath is String ? rawPath : '',
      listSelector: (json['list'] as String?) ?? '',
      fields: _fields(json['fields'], where: where),
      paging: SourcePagingRule.fromJson(json['paging']),
      filters: <SourceFilterRule>[
        for (final Object? f in (json['filters'] as List<Object?>?) ?? const <Object?>[])
          if (f is Map) SourceFilterRule.fromJson(f.cast<String, Object?>()),
      ],
    );
  }
}

/// 翻页规则：下一页选择器，或纯页码拼 URL。
class SourcePagingRule {
  const SourcePagingRule({this.nextSelector, this.totalPageSelector});

  static const SourcePagingRule none = SourcePagingRule();

  /// 存在时优先用「下一页链接」翻页。
  final String? nextSelector;

  /// 存在且列表为空时，用于判断是否已到最后一页。
  final String? totalPageSelector;

  bool get hasNextSelector => nextSelector != null && nextSelector!.isNotEmpty;

  static SourcePagingRule fromJson(Object? json) {
    if (json is! Map) {
      return none;
    }
    final Map<String, Object?> map = json.cast<String, Object?>();
    return SourcePagingRule(
      nextSelector: map['next'] as String?,
      totalPageSelector: map['total'] as String?,
    );
  }
}

/// 一本书在源里的详情页规则。
class SourceBookInfoRule {
  const SourceBookInfoRule({required this.path, this.fields = const <String, String>{}});

  final String path;
  final Map<String, String> fields;

  static SourceBookInfoRule fromJson(Map<String, Object?> json) {
    return SourceBookInfoRule(
      path: _str(json['path'], field: 'bookInfo.path'),
      fields: _fields(json['fields'], where: 'bookInfo'),
    );
  }
}

/// 目录（卷 + 章节）规则。
class SourceVolumesRule {
  const SourceVolumesRule({
    required this.path,
    required this.chapterSelector,
    this.volumeSelector,
    this.volumeTitleField,
    this.chapterFields = const <String, String>{},
  });

  final String path;
  final String chapterSelector;
  final String? volumeSelector;
  final String? volumeTitleField;
  final Map<String, String> chapterFields;

  static SourceVolumesRule fromJson(Map<String, Object?> json) {
    return SourceVolumesRule(
      path: _str(json['path'], field: 'volumes.path'),
      chapterSelector: _str(json['chapters'], field: 'volumes.chapters'),
      volumeSelector: json['volumes'] as String?,
      volumeTitleField: json['volumeTitle'] as String?,
      chapterFields: _fields(json['chapterFields'], where: 'volumes.chapterFields'),
    );
  }
}

/// 正文规则。
class SourceChapterRule {
  const SourceChapterRule({
    required this.path,
    required this.contentSelector,
    this.paragraphSeparator,
    this.titleSelector,
    this.nextSelector,
    this.prevSelector,
    this.imageSelector,
  });

  final String path;

  /// 段落容器选择器：匹配到的每个节点文本作为一段。
  final String contentSelector;

  /// 选定 contentSelector 的**第一个**节点后，按此分隔符切段（与 contentSelector 二选一）。
  final String? paragraphSeparator;

  final String? titleSelector;
  final String? nextSelector;
  final String? prevSelector;
  final String? imageSelector;

  static SourceChapterRule fromJson(Map<String, Object?> json) {
    return SourceChapterRule(
      path: _str(json['path'], field: 'chapter.path'),
      contentSelector: _str(json['content'], field: 'chapter.content'),
      paragraphSeparator: json['paragraphSeparator'] as String?,
      titleSelector: json['title'] as String?,
      nextSelector: json['next'] as String?,
      prevSelector: json['prev'] as String?,
      imageSelector: json['image'] as String?,
    );
  }
}

/// 一个在线数据源的完整声明。
class SourceManifest {
  const SourceManifest({
    required this.id,
    required this.name,
    required this.apiVersion,
    required this.baseUrl,
    required this.charset,
    this.author = '',
    this.description = '',
    this.versionCode = 1,
    this.versionName = '',
    this.minAppVersion = '',
    this.headers = const <String, String>{},
    this.capabilities = const <SourceCapability>{SourceCapability.chapter},
    this.permits = 4,
    this.cacheTtlMs = 30 * 60 * 1000,
    this.cacheMaxEntries = 32,
    this.searchTypes = const <SourceSearchTypeRule>[],
    this.searchRule,
    this.exploreRules = const <SourceExploreRule>[],
    this.bookInfoRule,
    this.volumesRule,
    this.chapterRule,
    this.updateUrl = '',
  });

  final String id;
  final String name;
  final String author;
  final String description;
  final int apiVersion;
  final int versionCode;
  final String versionName;
  final String minAppVersion;
  final String baseUrl;
  final String charset;

  /// 请求头，值里可用 `{base}` 占位。
  final Map<String, String> headers;

  final Set<SourceCapability> capabilities;

  /// 单源并发上限（对应上游 WebBookDataSource.permits）。
  final int permits;

  final int cacheTtlMs;
  final int cacheMaxEntries;

  final List<SourceSearchTypeRule> searchTypes;
  final SourceListRule? searchRule;
  final List<SourceExploreRule> exploreRules;
  final SourceBookInfoRule? bookInfoRule;
  final SourceVolumesRule? volumesRule;
  final SourceChapterRule? chapterRule;

  final String updateUrl;

  bool supports(SourceCapability capability) => capabilities.contains(capability);

  /// 解析并**严格校验** manifest：任何结构性错误都给出可读原因。
  ///
  /// 与上游「未知组件降级为 ErrorComponent」的取向一致——坏声明不应该
  /// 悄悄变成一台空转的源，而应该在安装阶段就被挡下来。
  static SourceManifest fromJson(Map<String, Object?> json) {
    final String id = _str(json['id'], field: 'id');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(id)) {
      throw SourceManifestException('源 id 非法（只允许字母数字._-）: $id');
    }
    final String baseUrl = _str(json['baseUrl'], field: 'baseUrl');
    final Uri? base = Uri.tryParse(baseUrl);
    if (base == null || !base.hasScheme) {
      throw SourceManifestException('baseUrl 非法: $baseUrl');
    }

    final Set<SourceCapability> capabilities = <SourceCapability>{};
    final Object? rawCaps = json['capabilities'];
    if (rawCaps is List) {
      for (final Object? c in rawCaps) {
        final SourceCapability? cap = _capabilityFromName(c?.toString() ?? '');
        if (cap != null) {
          capabilities.add(cap); // 未知能力静默忽略，向前兼容
        }
      }
    }
    if (capabilities.isEmpty) {
      capabilities.add(SourceCapability.chapter);
    }

    final SourceBookInfoRule? bookInfo = _sub(json['bookInfo'], SourceBookInfoRule.fromJson);
    final SourceChapterRule? chapter = _sub(json['chapter'], SourceChapterRule.fromJson);

    final Map<String, Object?>? searchJson = _mapOrNull(json['search']);
    final List<SourceSearchTypeRule> searchTypes = <SourceSearchTypeRule>[
      for (final Object? t in (searchJson?['types'] as List<Object?>?) ?? const <Object?>[])
        if (t is Map) SourceSearchTypeRule.fromJson(t.cast<String, Object?>()),
    ];

    final SourceManifest manifest = SourceManifest(
      id: id,
      name: (json['name'] as String?) ?? id,
      author: (json['author'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      apiVersion: (json['apiVersion'] as num?)?.toInt() ?? 1,
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 1,
      versionName: (json['versionName'] as String?) ?? '',
      minAppVersion: (json['minAppVersion'] as String?) ?? '',
      baseUrl: baseUrl,
      charset: ((json['charset'] as String?) ?? 'utf-8').toLowerCase(),
      headers: <String, String>{
        for (final MapEntry<String, Object?> e
            in ((json['headers'] as Map?) ?? const <String, Object?>{}).cast<String, Object?>().entries)
          e.key: e.value?.toString() ?? '',
      },
      capabilities: capabilities,
      permits: (json['permits'] as num?)?.toInt() ?? 4,
      cacheTtlMs: (json['cacheTtlMs'] as num?)?.toInt() ?? 30 * 60 * 1000,
      cacheMaxEntries: (json['cacheMaxEntries'] as num?)?.toInt() ?? 32,
      searchTypes: searchTypes,
      searchRule: searchJson == null
          ? null
          : SourceListRule.fromJson(searchJson, where: 'search'),
      exploreRules: <SourceExploreRule>[
        for (final Object? e in (json['explore'] as List<Object?>?) ?? const <Object?>[])
          if (e is Map) SourceExploreRule.fromJson(e.cast<String, Object?>()),
      ],
      bookInfoRule: bookInfo,
      volumesRule: _sub(json['volumes'], SourceVolumesRule.fromJson),
      chapterRule: chapter,
      updateUrl: (json['updateUrl'] as String?) ?? '',
    );

    manifest._validate();
    return manifest;
  }

  /// 能力与规则必须自洽：声明了 search 却没有搜索规则 = 装了个坏源。
  void _validate() {
    if (supports(SourceCapability.search) && (searchRule == null || searchTypes.isEmpty)) {
      throw const SourceManifestException('声明了 search 能力但缺少 search 规则或 types');
    }
    if (supports(SourceCapability.explore) && exploreRules.isEmpty) {
      throw const SourceManifestException('声明了 explore 能力但缺少 explore 规则');
    }
    if (supports(SourceCapability.bookInfo) && bookInfoRule == null) {
      throw const SourceManifestException('声明了 bookInfo 能力但缺少 bookInfo 规则');
    }
    if (supports(SourceCapability.volumes) && volumesRule == null) {
      throw const SourceManifestException('声明了 volumes 能力但缺少 volumes 规则');
    }
    if (supports(SourceCapability.chapter) && chapterRule == null) {
      throw const SourceManifestException('声明了 chapter 能力但缺少 chapter 规则');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'author': author,
        'description': description,
        'apiVersion': apiVersion,
        'versionCode': versionCode,
        'versionName': versionName,
        'minAppVersion': minAppVersion,
        'baseUrl': baseUrl,
        'charset': charset,
        'headers': headers,
        'capabilities': <String>[for (final SourceCapability c in capabilities) c.name],
        'permits': permits,
        'cacheTtlMs': cacheTtlMs,
        'cacheMaxEntries': cacheMaxEntries,
      };
}

/// 探索页规则：一个可滚动的书单（可选带过滤器）。
class SourceExploreRule {
  const SourceExploreRule({
    required this.id,
    required this.title,
    required this.list,
  });

  final String id;
  final String title;
  final SourceListRule list;

  static SourceExploreRule fromJson(Map<String, Object?> json) {
    final String id = _str(json['id'], field: 'explore.id');
    return SourceExploreRule(
      id: id,
      title: (json['title'] as String?) ?? id,
      list: SourceListRule.fromJson(json, where: 'explore[$id]', requirePath: true),
    );
  }
}

SourceCapability? _capabilityFromName(String name) {
  for (final SourceCapability c in SourceCapability.values) {
    if (c.name == name) {
      return c;
    }
  }
  return null;
}

String _str(Object? value, {required String field}) {
  if (value is! String || value.isEmpty) {
    throw SourceManifestException('缺少必填字段 $field');
  }
  return value;
}

double _num(Object? value, double fallback) => value is num ? value.toDouble() : fallback;

Map<String, String> _fields(Object? json, {required String where}) {
  if (json == null) {
    return const <String, String>{};
  }
  if (json is! Map) {
    throw SourceManifestException('$where.fields 必须是对象');
  }
  return <String, String>{
    for (final MapEntry<Object?, Object?> e in json.entries)
      e.key.toString(): e.value?.toString() ?? '',
  };
}

Map<String, Object?>? _mapOrNull(Object? json) {
  if (json is! Map) {
    return null;
  }
  return json.cast<String, Object?>();
}

T? _sub<T>(Object? json, T Function(Map<String, Object?>) build) {
  final Map<String, Object?>? map = _mapOrNull(json);
  return map == null ? null : build(map);
}
