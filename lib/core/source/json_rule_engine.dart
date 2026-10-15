import 'package:html/dom.dart' as dom;

import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/source/field_spec.dart';
import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/core/source/url_template.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/models/source_manifest.dart';
import 'package:novel_reader/services/source/cached_http.dart';

/// 声明式规则引擎：唯一需要的「源实现」。
///
/// 上游要新增一个数据源就得写一个 Kotlin 类、编译、装 APK；
/// 这里新增一个源 = 写一份 JSON manifest。
class JsonRuleEngine implements SourceEngine {
  JsonRuleEngine({required this.manifest, required CachedHttp http}) : _http = http;

  @override
  final SourceManifest manifest;

  final CachedHttp _http;

  /// 字段名约定：这些 key 会映射到 [SourceBook] 的固定属性。
  static const String _fTitle = 'title';
  static const String _fId = 'id';
  static const String _fAuthor = 'author';
  static const String _fCover = 'cover';
  static const String _fDescription = 'description';
  static const String _fTags = 'tags';
  static const String _fComplete = 'isComplete';

  Uri get baseUri => Uri.parse(manifest.baseUrl);

  /// 请求头：manifest 里的 `{base}` 会被替换成 baseUrl。
  Map<String, String> get headers => <String, String>{
        for (final MapEntry<String, String> e in manifest.headers.entries)
          e.key: e.value.replaceAll('{base}', manifest.baseUrl),
      };

  Uri _uriFor(String path, Map<String, String> vars) {
    final UrlTemplate template = UrlTemplate(path, vars: <String, String>{'base': manifest.baseUrl});
    final Uri uri = template.expand(vars, base: baseUri);
    if (!uri.hasScheme) {
      throw SourceError(SourceErrorKind.invalid, 'URL 模板无法解析为绝对地址: $path');
    }
    return uri;
  }

  Future<dom.Document> _document(
    String path,
    Map<String, String> vars, {
    bool bypassCache = false,
  }) {
    final Uri uri = _uriFor(path, vars);
    return _http.getDocument(
      uri,
      charset: manifest.charset,
      headers: headers,
      ttl: Duration(milliseconds: manifest.cacheTtlMs),
      bypassCache: bypassCache,
    );
  }

  // ---------------------------------------------------------------- 书目详情

  @override
  Future<SourceBookDetail> bookDetail(String bookId) async {
    final SourceBook book = await _loadBookInfo(bookId);
    final List<SourceVolume> volumes = await this.volumes(bookId);
    return SourceBookDetail(book: book, volumes: volumes);
  }

  Future<SourceBook> _loadBookInfo(String bookId) async {
    final SourceBookInfoRule? rule = manifest.bookInfoRule;
    if (rule == null) {
      // 没有详情规则时退化成「只知道 id 的书」，目录与正文仍可读
      return SourceBook(sourceId: manifest.id, bookId: bookId, title: bookId);
    }
    final dom.Document doc = await _document(rule.path, <String, String>{'id': _enc(bookId)});
    final Map<String, FieldSpec> fields = FieldSpec.parseMap(rule.fields);
    final dom.Element root = _rootOf(doc);
    return SourceBook(
      sourceId: manifest.id,
      bookId: bookId,
      title: _first(fields[_fTitle], root, baseUri) ?? bookId,
      author: _first(fields[_fAuthor], root, baseUri) ?? '',
      coverUrl: _absolute(_first(fields[_fCover], root, baseUri)),
      description: _first(fields[_fDescription], root, baseUri) ?? '',
      tags: fields[_fTags]?.extractAll(root, base: baseUri) ?? const <String>[],
      isComplete: _boolOf(_first(fields[_fComplete], root, baseUri)),
    );
  }

  // ------------------------------------------------------------------ 目录

  @override
  Future<List<SourceVolume>> volumes(String bookId) async {
    final SourceVolumesRule? rule = manifest.volumesRule;
    if (rule == null) {
      throw const SourceError(SourceErrorKind.unsupported, '该源没有声明目录规则');
    }
    final dom.Document doc = await _document(rule.path, <String, String>{'id': _enc(bookId)});
    return parseVolumes(doc, rule);
  }

  /// 目录解析独立成公开方法，便于用静态 HTML fixture 单测（不碰网络）。
  List<SourceVolume> parseVolumes(dom.Document doc, SourceVolumesRule rule) {
    final Map<String, FieldSpec> chapterFields = FieldSpec.parseMap(rule.chapterFields);
    final List<SourceVolume> volumes = <SourceVolume>[];

    final String? volumeSelector = rule.volumeSelector;
    final List<dom.Element> scopes;
    if (volumeSelector == null || volumeSelector.isEmpty) {
      scopes = <dom.Element>[_rootOf(doc)];
    } else {
      // 必须是可增长的：下面找不到分卷时要回退成「整页一个卷」
      scopes = doc.querySelectorAll(volumeSelector).toList();
      if (scopes.isEmpty) {
        scopes.add(_rootOf(doc));
      }
    }

    for (final dom.Element scope in scopes) {
      final List<SourceChapter> chapters = <SourceChapter>[];
      final Iterable<dom.Element> anchors = scope.querySelectorAll(rule.chapterSelector);
      for (final dom.Element anchor in anchors) {
        final String title =
            (chapterFields[_fTitle]?.extractFirst(anchor, base: baseUri) ?? anchor.text).trim();
        final String id =
            chapterFields[_fId]?.extractFirst(anchor, base: baseUri) ?? (anchor.attributes['href'] ?? '');
        if (id.isEmpty) {
          continue; // 没 id 的条目无法跳转，直接丢
        }
        chapters.add(SourceChapter(id: id.trim(), title: title.isEmpty ? id : title));
      }
      if (chapters.isEmpty) {
        continue;
      }
      final String volumeTitle = rule.volumeTitleField == null
          ? ''
          : (FieldSpec.parse(rule.volumeTitleField!).extractFirst(scope, base: baseUri) ?? '');
      volumes.add(SourceVolume(title: volumeTitle, chapters: chapters));
    }

    if (volumes.isEmpty) {
      throw const SourceError(SourceErrorKind.parse, '目录解析结果为空，选择器可能已失效');
    }
    return volumes;
  }

  // ------------------------------------------------------------------ 正文

  @override
  Future<SourceChapterContent> chapterContent(
    String chapterId, {
    String? bookId,
    bool refresh = false,
  }) async {
    final SourceChapterRule? rule = manifest.chapterRule;
    if (rule == null) {
      throw const SourceError(SourceErrorKind.unsupported, '该源没有声明正文规则');
    }
    final dom.Document doc = await _document(
      rule.path,
      <String, String>{
        'chapterId': _enc(chapterId),
        'id': _enc(chapterId),
        if (bookId != null) 'bookId': _enc(bookId),
      },
      bypassCache: refresh,
    );

    return SourceChapterContent(
      id: chapterId,
      title: rule.titleSelector == null
          ? ''
          : (FieldSpec.parse(rule.titleSelector!).extractFirst(_rootOf(doc), base: baseUri) ?? ''),
      blocks: parseParagraphs(doc, rule),
      prevId: _idOf(rule.prevSelector, doc),
      nextId: _idOf(rule.nextSelector, doc),
    );
  }

  /// 正文段落解析（同样独立出来便于离线单测）。
  List<ParagraphBlock> parseParagraphs(dom.Document doc, SourceChapterRule rule) {
    final List<String> raw = <String>[];
    final String? separator = rule.paragraphSeparator;
    if (separator != null && separator.isNotEmpty) {
      final dom.Element? container = doc.querySelector(rule.contentSelector);
      final String text = container?.text ?? '';
      raw.addAll(text.split(separator));
    } else {
      for (final dom.Element element in doc.querySelectorAll(rule.contentSelector)) {
        raw.add(element.text);
      }
    }

    final List<ParagraphBlock> blocks = <ParagraphBlock>[];
    for (final String piece in raw) {
      final String text = _normalizeParagraph(piece);
      if (text.isEmpty) {
        continue;
      }
      blocks.add(ParagraphBlock(text: text, kind: _kindOf(text)));
    }
    if (blocks.isEmpty) {
      throw const SourceError(SourceErrorKind.parse, '正文解析结果为空，选择器可能已失效');
    }
    return blocks;
  }

  String? _idOf(String? selector, dom.Document doc) {
    if (selector == null || selector.isEmpty) {
      return null;
    }
    final String? value = FieldSpec.parse(selector).extractFirst(_rootOf(doc), base: baseUri);
    return (value == null || value.isEmpty) ? null : value;
  }

  // ------------------------------------------------------------- 探索 / 搜索

  @override
  Future<List<SourceBook>> explore(
    String exploreId, {
    Map<String, String> filterChoices = const <String, String>{},
    Map<String, double> filterSliders = const <String, double>{},
    Map<String, bool> filterToggles = const <String, bool>{},
    int page = 1,
  }) async {
    final SourceExploreRule? rule =
        manifest.exploreRules.where((SourceExploreRule r) => r.id == exploreId).firstOrNull;
    if (rule == null) {
      throw SourceError(SourceErrorKind.unsupported, '源里没有探索页: $exploreId');
    }
    final String extra = _buildExtra(rule.list.filters, filterChoices, filterSliders, filterToggles);
    final dom.Document doc = await _document(rule.list.path, <String, String>{
      'extra': extra,
      'page': '$page',
    });
    return parseList(doc, rule.list);
  }

  /// 列表解析（同样独立，测起来不碰网络）。
  List<SourceBook> parseList(dom.Document doc, SourceListRule rule) {
    final Map<String, FieldSpec> fields = FieldSpec.parseMap(rule.fields);
    final List<dom.Element> items = rule.listSelector.isEmpty
        ? <dom.Element>[_rootOf(doc)]
        : doc.querySelectorAll(rule.listSelector).toList(growable: false);

    final List<SourceBook> books = <SourceBook>[];
    for (final dom.Element item in items) {
      final String? id = fields[_fId]?.extractFirst(item, base: baseUri);
      if (id == null || id.trim().isEmpty) {
        continue;
      }
      books.add(SourceBook(
        sourceId: manifest.id,
        bookId: id.trim(),
        title: fields[_fTitle]?.extractFirst(item, base: baseUri) ?? id.trim(),
        author: fields[_fAuthor]?.extractFirst(item, base: baseUri) ?? '',
        coverUrl: _absolute(fields[_fCover]?.extractFirst(item, base: baseUri)),
        description: fields[_fDescription]?.extractFirst(item, base: baseUri) ?? '',
        tags: fields[_fTags]?.extractAll(item, base: baseUri) ?? const <String>[],
      ));
    }
    return books;
  }

  @override
  Stream<SourceSearchEvent> search(String typeId, String keyword, {int maxPages = 1}) async* {
    final SourceListRule? rule = manifest.searchRule;
    final SourceSearchTypeRule? type =
        manifest.searchTypes.where((SourceSearchTypeRule t) => t.id == typeId).firstOrNull;
    if (rule == null || type == null) {
      yield SourceSearchEvent.error('该源不支持搜索方式: $typeId');
      return;
    }

    bool any = false;
    int page = 1;
    while (page <= maxPages) {
      final List<SourceBook> books;
      try {
        final dom.Document doc = await _document(type.path, <String, String>{
          'q': _enc(keyword),
          'kw': _enc(keyword),
          'page': '$page',
          'extra': '',
        });
        books = parseList(doc, rule);
      } on SourceError catch (e) {
        // 允许「部分成功」：前面页已产出的结果不因后面页失败而丢弃
        yield SourceSearchEvent.error(e.message);
        return;
      }
      if (books.isEmpty) {
        if (!any) {
          yield const SourceSearchEvent.empty();
        }
        yield const SourceSearchEvent.end();
        return;
      }
      for (final SourceBook book in books) {
        any = true;
        yield SourceSearchEvent.book(book);
      }
      if (page >= maxPages) {
        break;
      }
      page++;
    }
    yield const SourceSearchEvent.end();
  }

  @override
  Future<bool> ping() async {
    try {
      if (manifest.exploreRules.isNotEmpty) {
        await explore(manifest.exploreRules.first.id);
      } else if (manifest.bookInfoRule != null) {
        await _document(manifest.bookInfoRule!.path, <String, String>{'id': '1'});
      } else {
        // 没有可探的业务页面时，至少要真的碰一次站点。
        // 之前这里直接 return true，等于对任何配置都宣称「源是活的」，
        // 一个指向保留端口的源也会被判为可达。
        await _http.getText(
          baseUri,
          charset: manifest.charset,
          headers: headers,
          ttl: Duration(milliseconds: manifest.cacheTtlMs),
        );
      }
      return true;
    } on Object {
      return false;
    }
  }

  // -------------------------------------------------------------------- 工具

  /// 统一的查询根。
  ///
  /// package:html 里 `Document` 与 `Element` 的公共超类型是私有的
  /// （`_ElementAndDocument`），写 `doc.documentElement ?? doc` 会得到一个
  /// 赋不给 `Element` 的类型，所以一律收敛到具体的 Element。
  static dom.Element _rootOf(dom.Document doc) {
    final dom.Element? root = doc.documentElement ?? doc.querySelector('html') ?? doc.body;
    if (root == null) {
      throw const SourceError(SourceErrorKind.parse, '页面没有可用的根节点');
    }
    return root;
  }

  /// 把过滤器选择拼成 URL 附加片段。
  static String _buildExtra(
    List<SourceFilterRule> filters,
    Map<String, String> choices,
    Map<String, double> sliders,
    Map<String, bool> toggles,
  ) {
    final StringBuffer buffer = StringBuffer();
    for (final SourceFilterRule filter in filters) {
      buffer.write(filter.expand(
        choice: choices[filter.key] ?? filter.defaultChoice,
        slider: sliders[filter.key] ?? filter.defaultValue,
        toggle: toggles[filter.key] ?? (filter.defaultChoice == 'true'),
      ));
    }
    return buffer.toString();
  }

  static String? _first(FieldSpec? spec, dom.Element root, Uri base) =>
      spec?.extractFirst(root, base: base);

  static bool? _boolOf(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final String v = value.trim();
    if (RegExp(r'完结|已完结|完成|true|yes|是').hasMatch(v)) {
      return true;
    }
    if (RegExp(r'连载|未完|false|no|否').hasMatch(v)) {
      return false;
    }
    return null;
  }

  /// 相对地址补全。上游要求每个源自己写绝对化逻辑，这里统一兜住。
  String _absolute(String? value) {
    if (value == null || value.isEmpty) {
      return '';
    }
    final Uri? parsed = Uri.tryParse(value.trim());
    if (parsed == null) {
      return '';
    }
    if (parsed.hasScheme) {
      return parsed.toString();
    }
    return baseUri.resolveUri(parsed).toString();
  }

  /// 段落规范化：压掉 HTML 里常见的缩进/空行噪声，保留段落内空格。
  static String _normalizeParagraph(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t\u00a0\u3000]+'), ' ')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
  }

  /// 廉价的行级类型推断：只在明显像标题时才标 heading。
  static ParagraphKind _kindOf(String text) {
    if (text.length <= 40 &&
        RegExp(r'^(第\s*[0-9一二三四五六七八九十百千]+\s*[章节回卷])').hasMatch(text)) {
      return ParagraphKind.heading;
    }
    return ParagraphKind.paragraph;
  }

  static String _enc(String value) => Uri.encodeComponent(value);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
