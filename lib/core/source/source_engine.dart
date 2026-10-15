import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/models/source_manifest.dart';

/// 源错误的类别。UI 据此决定是「重试」还是「换个源」。
enum SourceErrorKind {
  /// 请求发出前就失败：URL 模板缺变量、manifest 不支持该能力。
  invalid,

  /// 网络层失败（DNS/连接/超时）。
  network,

  /// 服务端返回非 2xx。
  http,

  /// 拿到了响应但解析不出需要的字段。
  parse,

  /// 明确的 404 / 资源不存在。
  notFound,

  /// 源没有声明该能力。
  unsupported,

  /// 上层主动取消。
  cancelled,
}

/// 类型化的源错误。
///
/// 上游把 `Result<_, WebRequestError>` 一路透传，但有一处只取 error 的字符串
/// 形式导致错误退化成 `SearchResult.Error("Failed to request the web page")`
/// ——这里保留结构，让 UI 能区分「网络不通」和「选择器写错了」。
class SourceError implements Exception {
  const SourceError(this.kind, this.message, {this.detail});

  final SourceErrorKind kind;
  final String message;
  final String? detail;

  bool get isRetryable =>
      kind == SourceErrorKind.network || kind == SourceErrorKind.http;

  @override
  String toString() => 'SourceError(${kind.name}): $message';
}

/// 一个在线数据源的运行时接口。
///
/// 只保留「读」这一侧：源不负责写库、不持有 UI 状态、不返回框架类型
/// （上游把 `Flow`/`@Composable`/`CoroutineScope` 写进数据源接口，
/// 导致源无法脱离 Compose 测试）。
abstract class SourceEngine {
  /// 源声明。
  SourceManifest get manifest;

  /// 书目详情（含目录）。要求源声明 `bookInfo` 或 `volumes` 能力。
  Future<SourceBookDetail> bookDetail(String bookId);

  /// 只取目录，跳过详情页（部分源目录与详情同页，实现可复用缓存）。
  Future<List<SourceVolume>> volumes(String bookId);

  /// 章节正文。
  ///
  /// [refresh] 为 true 时**同时**绕过 HTTP 层缓存与上层缓存——
  /// 只跳一层会得到「刷新了但还是旧内容」的假刷新。
  Future<SourceChapterContent> chapterContent(
    String chapterId, {
    String? bookId,
    bool refresh = false,
  });

  /// 探索页某一行/某一页的书单。
  Future<List<SourceBook>> explore(
    String exploreId, {
    Map<String, String> filterChoices = const <String, String>{},
    Map<String, double> filterSliders = const <String, double>{},
    Map<String, bool> filterToggles = const <String, bool>{},
    int page = 1,
  });

  /// 搜索。返回事件流，允许逐条产出。
  Stream<SourceSearchEvent> search(String typeId, String keyword, {int maxPages = 1});

  /// 探测源是否可用（拿一个轻量页面探活）。失败不抛，返回 false。
  Future<bool> ping();
}

/// 便捷读取：`implements` 不继承实现，所以 id/name 用扩展提供，
/// 避免每个引擎都重复写两行样板。
extension SourceEngineInfo on SourceEngine {
  String get id => manifest.id;

  String get name => manifest.name;
}
