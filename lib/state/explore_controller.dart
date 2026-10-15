import 'package:flutter/foundation.dart';

import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/data/repositories/online_book_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/models/source_manifest.dart';
import 'package:novel_reader/services/source/source_registry.dart';

/// 一档探索页（一个 tab）的状态。
class ExploreRowState {
  const ExploreRowState({
    this.books = const <SourceBook>[],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.page = 1,
    this.reachedEnd = false,
    this.filterChoices = const <String, String>{},
    this.filterSliders = const <String, double>{},
    this.filterToggles = const <String, bool>{},
  });

  final List<SourceBook> books;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int page;
  final bool reachedEnd;

  final Map<String, String> filterChoices;
  final Map<String, double> filterSliders;
  final Map<String, bool> filterToggles;

  bool get isEmpty => books.isEmpty && !isLoading && error == null;

  ExploreRowState copyWith({
    List<SourceBook>? books,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    int? page,
    bool? reachedEnd,
    Map<String, String>? filterChoices,
    Map<String, double>? filterSliders,
    Map<String, bool>? filterToggles,
  }) {
    return ExploreRowState(
      books: books ?? this.books,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      page: page ?? this.page,
      reachedEnd: reachedEnd ?? this.reachedEnd,
      filterChoices: filterChoices ?? this.filterChoices,
      filterSliders: filterSliders ?? this.filterSliders,
      filterToggles: filterToggles ?? this.filterToggles,
    );
  }
}

/// 探索页与搜索的状态。
///
/// 只依赖注册表与在线仓库，不知道 SourceController 的存在：
/// 页面负责把「当前激活源」推给它，控制器之间不互相订阅。
class ExploreController extends ChangeNotifier {
  ExploreController({required SourceRegistry registry, required OnlineBookRepository repository})
      : _registry = registry,
        _repository = repository;

  final SourceRegistry _registry;
  final OnlineBookRepository _repository;

  String? _sourceId;
  final Map<String, ExploreRowState> _rows = <String, ExploreRowState>{};
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  // 搜索状态
  List<SourceBook> _searchResults = <SourceBook>[];
  bool _isSearching = false;
  String? _searchError;
  String _searchTypeId = '';
  String _lastKeyword = '';

  String? get sourceId => _sourceId;

  bool get hasSource => _sourceId != null && _registry.engineFor(_sourceId!) != null;

  SourceManifest? get manifest {
    final String? id = _sourceId;
    return id == null ? null : _registry.entryOf(id)?.manifest;
  }

  /// 当前源声明里支持搜索的方式。
  List<SourceSearchTypeRule> get searchTypes => manifest?.searchTypes ?? const <SourceSearchTypeRule>[];

  bool get canSearch => manifest?.supports(SourceCapability.search) ?? false;

  /// 当前源声明的探索页。
  List<SourceExploreRule> get exploreRules => manifest?.exploreRules ?? const <SourceExploreRule>[];

  String get searchTypeId => _searchTypeId;

  List<SourceBook> get searchResults => _searchResults;

  bool get isSearching => _isSearching;

  String? get searchError => _searchError;

  String get lastKeyword => _lastKeyword;

  ExploreRowState stateOf(String ruleId) => _rows[ruleId] ?? const ExploreRowState();

  /// 切换源：清空已有状态并预载第一个探索页。
  Future<void> bindSource(String? sourceId) async {
    if (_sourceId == sourceId) {
      return;
    }
    _sourceId = sourceId;
    _rows.clear();
    _inFlight.clear();
    clearSearch();
    notifyListeners();

    if (sourceId != null && exploreRules.isNotEmpty) {
      await load(exploreRules.first.id);
    }
  }

  Future<void> load(String ruleId, {bool refresh = false}) {
    // 同一档的并发加载合并成一次，避免下拉刷新与首屏加载互相覆盖
    final Future<void>? running = _inFlight[ruleId];
    if (running != null) {
      return running;
    }
    final Future<void> task = _load(ruleId, refresh: refresh, append: false)
        .whenComplete(() => _inFlight.remove(ruleId));
    _inFlight[ruleId] = task;
    return task;
  }

  Future<void> loadMore(String ruleId) async {
    final ExploreRowState state = stateOf(ruleId);
    if (state.isLoading || state.isLoadingMore || state.reachedEnd) {
      return;
    }
    await _load(ruleId, refresh: false, append: true);
  }

  Future<void> _load(String ruleId, {required bool refresh, required bool append}) async {
    final String? sourceId = _sourceId;
    if (sourceId == null) {
      return;
    }
    final ExploreRowState previous = stateOf(ruleId);
    final int nextPage = append ? previous.page + 1 : 1;
    _rows[ruleId] = previous.copyWith(
      isLoading: !append,
      isLoadingMore: append,
      clearError: true,
    );
    notifyListeners();

    try {
      final List<SourceBook> fetched = await _repository.explore(
        sourceId,
        ruleId,
        filterChoices: previous.filterChoices,
        filterSliders: previous.filterSliders,
        filterToggles: previous.filterToggles,
        page: nextPage,
      );
      _rows[ruleId] = stateOf(ruleId).copyWith(
        books: append ? <SourceBook>[...stateOf(ruleId).books, ...fetched] : fetched,
        isLoading: false,
        isLoadingMore: false,
        page: nextPage,
        // 返回空就认为到底了：多数站点的「下一页」在末页会返回空列表
        reachedEnd: fetched.isEmpty,
        clearError: true,
      );
    } on SourceError catch (e) {
      _rows[ruleId] = stateOf(ruleId).copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e.message,
      );
    } on Object catch (e) {
      _rows[ruleId] = stateOf(ruleId).copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: '$e',
      );
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ 过滤器

  Future<void> setFilterChoice(String ruleId, String key, String value) async {
    final ExploreRowState state = stateOf(ruleId);
    _rows[ruleId] = state.copyWith(
      filterChoices: <String, String>{...state.filterChoices, key: value},
    );
    await load(ruleId, refresh: true);
  }

  Future<void> setFilterSlider(String ruleId, String key, double value) async {
    final ExploreRowState state = stateOf(ruleId);
    _rows[ruleId] = state.copyWith(
      filterSliders: <String, double>{...state.filterSliders, key: value},
    );
    await load(ruleId, refresh: true);
  }

  Future<void> setFilterToggle(String ruleId, String key, bool value) async {
    final ExploreRowState state = stateOf(ruleId);
    _rows[ruleId] = state.copyWith(
      filterToggles: <String, bool>{...state.filterToggles, key: value},
    );
    await load(ruleId, refresh: true);
  }

  // -------------------------------------------------------------------- 搜索

  void setSearchType(String typeId) {
    if (_searchTypeId == typeId) {
      return;
    }
    _searchTypeId = typeId;
    notifyListeners();
  }

  void clearSearch() {
    _searchResults = <SourceBook>[];
    _searchError = null;
    _isSearching = false;
    _lastKeyword = '';
    notifyListeners();
  }

  /// 搜索：逐条收集事件流，允许「部分结果 + 错误」同时出现。
  Future<void> search(String keyword) async {
    final String? sourceId = _sourceId;
    final String trimmed = keyword.trim();
    if (sourceId == null || trimmed.isEmpty) {
      return;
    }
    if (_searchTypeId.isEmpty && searchTypes.isNotEmpty) {
      _searchTypeId = searchTypes.first.id;
    }

    _isSearching = true;
    _searchError = null;
    _searchResults = <SourceBook>[];
    _lastKeyword = trimmed;
    notifyListeners();

    try {
      await for (final SourceSearchEvent event
          in _repository.search(sourceId, _searchTypeId, trimmed, maxPages: 3)) {
        switch (event.kind) {
          case SourceSearchEventKind.book:
            final SourceBook? book = event.book;
            if (book != null) {
              _searchResults = <SourceBook>[..._searchResults, book];
              notifyListeners();
            }
          case SourceSearchEventKind.empty:
            break;
          case SourceSearchEventKind.end:
            break;
          case SourceSearchEventKind.error:
            // 已经拿到的结果保留，错误额外提示——这就是「事件流」的价值
            _searchError = event.message;
            notifyListeners();
        }
      }
    } on Object catch (e) {
      _searchError = '$e';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------- 入库

  /// 查询源里这本书是否已在书架（用于把按钮显示成「去阅读」）。
  Future<Book?> findOnShelf(SourceBook book) {
    return _repository.findOnShelf(book.sourceId, book.bookId);
  }

  /// 拉取书目详情（详情页 + 目录），用于详情面板与「共 N 章」提示。
  Future<SourceBookDetail> loadDetail(SourceBook book) {
    return _repository.bookDetail(book.sourceId, book.bookId);
  }

  /// 整本抓取并放进书架。
  Future<Book> importToShelf(
    SourceBook book, {
    void Function(int fetched, int total, String title)? onProgress,
    Future<bool> Function()? shouldContinue,
  }) {
    return _repository.importToShelf(
      book: book,
      onProgress: onProgress,
      shouldContinue: shouldContinue,
    );
  }
}
