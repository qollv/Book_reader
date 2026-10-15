# 上游对标：LightNovelReader 可借鉴清单

> 对标对象：`dmzz-yyhyy/LightNovelReader`（Kotlin / Jetpack Compose，Apache-2.0，refactoring 分支）
> 本地只读副本：`../_ref_LightNovelReader/`（本文所有结论均来自实读源码，未修改上游任何文件）
> 本文档目的：把上游的设计决策映射到本项目 `novel_reader`（Flutter + sqflite + content.jsonl），
> 按优先级给出可落地方案，并标出**不要照抄**的部分。

---

## 落地状态（滚动更新）

| 项 | 章节 | 状态 | 落点 |
| --- | --- | --- | --- |
| 声明式在线数据源（含 ApiCompat 分组、先校验后落库、错误留痕）| §8 | ✅ 已实现 | `lib/core/source/`、`lib/services/source/` |
| 本地优先双发射 + 写穿缓存 + 离线降级 | §8 | ✅ 已实现 | `lib/data/repositories/online_book_repository.dart` |
| 编码显式化（先取 bytes 再按源声明解码）| §8 | ✅ 已实现 | `lib/services/source/text_decoder.dart` |
| 请求合并 / TTL 缓存 / 按异常类型重试 | §8 | ✅ 已实现 | `lib/services/source/cached_http.dart` |
| 探索页「行 + 过滤器」模型、搜索事件流 | §8 | ✅ 已实现 | `lib/models/source_manifest.dart`、`lib/core/source/json_rule_engine.dart` |
| 行为测试与可观测性钩子 | §4 | 🟡 部分（fixture 站点 + 界面冒烟已落地；Semantics 状态钩子待做）| `tool/fixture_site.dart`、`test/` |
| 内容组件模型（一份数据三用）| §1 | ⬜ 未做 | 规划在 M7 |
| 渲染期文本处理管线（净化规则 / 简繁）| §2 | ⬜ 未做 | 规划在 M7 |
| 分页缓存 key + 内容哈希锚点 | §3 | 🟡 部分（已有按排版参数的缓存；哈希锚点待做）| `lib/data/repositories/reader_repository.dart` |
| EPUB 导出 | §5 | ⬜ 未做 | 规划在 M7 |
| 双进度模型（current/max）| §6 | ⬜ 未做 | 规划在 M7 |
| 设置 kv 化（点分路径 + 读取端默认值）| §7 | ⬜ 未做 | 规划在 M7 |

**已确认不要照抄的**（详见 §10 与各章「坑」）：Compose `SubcomposeLayout` 增量分页、
APK 插件 + 反射注入、把 Flow/Composable 写进数据源接口、全局单源 + 切源清库 + 重启进程、
缓存读写 key 不一致、硬编码第三方站点 cookie、`delay(5s)` 固定节流。

---

## 0. 上游速览

| 维度 | 上游 | 我们 |
| --- | --- | --- |
| 技术栈 | Kotlin + Compose + Hilt + Room + Ktor/OkHttp + Jsoup + WorkManager | Flutter + Provider + sqflite + dio |
| 模块划分 | `:app` `:api` `:epub` `:proxy` `:plugin:js` `:compiler` `:benchmark` | 单一 Flutter 工程（`lib/` 分层） |
| 功能重心 | **在线多数据源阅读**（探索/搜索/插件源）、EPUB 导出、跨源数据隔离 | **本地导入阅读**（txt/md/docx）+ 智能排版 + 局域网互传 |
| 内容模型 | 组件化 JSON（paragraph/image 可扩展） | 纯文本段落（`ParagraphBlock`，kind 枚举） |
| 进度模型 | 每章双 map（current/max）+ **内容哈希锚点** | 单条「章+段+行」索引锚点 |
| 设置存储 | `user_data(path, group, type, value)` 点分路径 + 读取端默认值 | `settings(id=0, payload)` 单个 JSON blob |
| 测试 | `:benchmark` 行为测试框架（场景法 + 无障碍钩子） | 单元测试 + 若干 `test/zz_*.dart` 复现脚本 |

**最有价值的 4 个结构性启发**：内容组件模型（一份数据三种消费：分页渲染 / 文本规则 / EPUB）、
渲染期文本管道、分页缓存与内容哈希锚点、行为测试的可观测性钩子。

---

## 1. P0 —— 内容组件模型（最高优先级）

### 上游做法

`api/content/component/data/AbstractContentComponentData.kt`：

```kotlin
abstract class AbstractContentComponentData {
    abstract val id: Identifier                                  // "namespace:name"
    abstract fun toJsonElement(): JsonElement                     // 入库
    abstract fun toHtmlElement(context: Context): Element         // EPUB 导出复用同一份数据
}
```

段落不是字符串，而是**带样式的内联片段树**：

```kotlin
data class ParagraphComponentData(
    val paragraph: ParagraphNode,          // textNodes: List<TextNode>，每个 TextNode 自带 TextStyle
    override val index: Int,               // 分页切片序号（@Transient，不落库）
    override val split: Boolean            // 是否被切开（@Transient，不落库）
) : AbstractContentComponentData(), TextData<ParagraphComponentData>, Divisible<ParagraphComponentData>
```

三种能力是**按需实现的接口**，不是基类职责：

- `TextData<Self>.processText(f)` —— 实现了就自动接入文本处理管道（见 P0-2）
- `Divisible<Self>.split(height, width, ...)` —— 实现了就能被分页切开（见 P0-3）
- `id = "paragraph".ofAppId()` → `"lightnovelreader:paragraph"`

注册表在 `data/content/ContentComponentRepository.kt`，三张 map：`id → serializer` / `id → KClass` / `id → render`。

**关键容错**（上游 L42-58）：解析组件时缺 `id`、缺 `data`、未知 id 一律产出 `ErrorContentComponentData("...")`，
**绝不抛异常**——坏数据只毁掉那一个组件，不毁整章。id 里没 `:` 时自动补默认 namespace。

### 我们的现状

`lib/core/parsers/parsed_book.dart`：

```dart
enum ParagraphKind { paragraph, heading, quote, code }
class ParagraphBlock { final String text; final ParagraphKind kind; final int headingLevel; }
```

纯文本 + 枚举，没有内联样式、没有图片、没有可扩展 id。EPUB 导出（M6）目前无处复用。

### 落地方案

新增 `lib/core/content/`，保留 `ParagraphBlock` 作为**解析器输出**（不要废弃，解析层稳定），
增加一层可序列化内容模型供**渲染/导出/规则**三处消费：

```dart
// lib/core/content/component.dart
abstract class ContentComponent {
  const ContentComponent();
  String get id;                                     // 'paragraph' | 'image' | 'divider' | 'custom:xxx'
  Map<String, Object?> toJson();
  String toXhtml();                                  // EPUB 导出复用
  ContentComponent mapText(String Function(String) f) => this;   // 默认不可改，文本类覆写
}

class InlineSpan {                                   // 内联样式片段
  const InlineSpan(this.text, {this.bold = false, this.italic = false});
  final String text; final bool bold; final bool italic;
}

class ParagraphComponent extends ContentComponent {
  const ParagraphComponent(this.spans, {this.kind = ParagraphKind.paragraph, this.headingLevel = 1});
  final List<InlineSpan> spans;
  final ParagraphKind kind; final int headingLevel;
  @override String get id => 'paragraph';
  @override ContentComponent mapText(String Function(String) f) =>
      ParagraphComponent([for (final s in spans) InlineSpan(f(s.text), bold: s.bold, italic: s.italic)],
          kind: kind, headingLevel: headingLevel);
  @override String toXhtml() { /* kind → <p>/<h1..3>/<blockquote>/<pre>，见 P1-1 */ }
}

class ImageComponent extends ContentComponent {       // 漫画/插图场景，当前解析器不产出
  const ImageComponent(this.uri, {this.width, this.height});
  final String uri; final int? width, height;
  @override String get id => 'image';
}

class ErrorComponent extends ContentComponent {       // 对齐上游容错：坏数据降级，不炸整章
  const ErrorComponent(this.reason);
  final String reason;
  @override String get id => 'error';
}
```

```dart
// lib/core/content/registry.dart —— 静态两张表，不要学上游的反射注入
typedef ComponentParser = ContentComponent Function(Map<String, Object?> json);
typedef ComponentRenderer = Widget Function(BuildContext, ContentComponent);

final Map<String, ComponentParser> componentParsers = {
  'paragraph': ParagraphComponent.fromJson,
  'image': ImageComponent.fromJson,
};
ContentComponent parseComponent(Map<String, Object?> json) {
  final id = (json['id'] as String?)?.split(':').last;
  final data = json['data'];
  if (id == null || data is! Map<String, Object?>) return ErrorComponent('bad component');
  final p = componentParsers[id];
  if (p == null) return ErrorComponent('unknown component id=$id');
  try { return p(data); } catch (e) { return ErrorComponent('$id: $e'); }
}
```

**content.jsonl 就升级为每行一个组件**（仍是 jsonl，写盘格式向后兼容）：

```
{"id":"paragraph","data":{"kind":"paragraph","spans":[{"text":"第一段……"}]}}
{"id":"paragraph","data":{"kind":"heading","headingLevel":1,"spans":[{"text":"第一章"}]}}
```

迁移策略直接抄上游 Migration 17→18 的思路：**旧的纯文本行 → 包装成单个 paragraph 组件，解析失败原样保留**，
不要写"失败即丢弃"。解析器加一个 `contentVersion` 字段（写到 `books` 表），老库按 v1 读、按 v2 写。

涉及文件：`lib/core/parsers/*.dart`（输出组件）、`lib/core/content/*`（新增）、
`lib/data/repositories/reader_repository.dart`（读写）、`lib/core/pagination/paginator.dart`（改吃组件）。

---

## 2. P0 —— 渲染期文本处理管道（净化规则 / 简繁转换）

### 上游做法

规则模型极简（`data/format/FormattingRule.kt`）：

```kotlin
data class FormattingRule(
    val id: Int?, val name: String,
    val isRegex: Boolean, val match: String, val replacement: String, val isEnabled: Boolean
)
```

存 `formatting_rule(book_id, ...)`，**`book_id = ""` 即全局规则**。

作用顺序（`FormatRepository.processText`）：**先全部全局规则，再本书规则**，每步只处理 `isEnabled`。
两个细节值得抄：

1. `unescapeControlChars()` —— 允许用户在输入框里直接写 `\n` `\t` `\uXXXX` 并正确生效；
2. `PatternSyntaxException` 静默吞掉 —— 单条规则写错不影响其它规则（UI 侧另行校验并禁用保存）。

**生效位置是最关键的设计**（`processChapterContent`）：只改**内存副本**，绝不回写 `chapter_content`。

```kotlin
content = componentProcessor.apply {
    process { data: TextData<*> -> data.processText { text -> processText(bookId, text) } }
}.get()
```

同一套规则还作用于书名/作者/简介/卷名/章节名/探索页条目（`processBookInformation` / `processBookVolumes` /
`processExploreBooksRow`）。改一条规则立刻全书生效，**无需重新导入**。

管道注册顺序（`TextProcessingRepository.init`）：简繁转换先注册，自定义规则后注册 → **简繁先转换，规则后净化**。

### 我们的现状

`lib/core/text/text_normalizer.dart` 在**导入期**做续行合并等规范化，结果被烘焙进 `content.jsonl`。
用户无法事后调整，且没有可编辑的规则。

### 落地方案

```dart
// lib/models/formatting_rule.dart
class FormattingRule {
  const FormattingRule({this.id, required this.name, required this.isRegex,
      required this.match, required this.replacement, this.isEnabled = true, this.bookId = ''});
  final int? id; final String name; final bool isRegex;
  final String match; final String replacement; final bool isEnabled;
  final String bookId;                      // '' = 全局
}
```

```dart
// lib/core/text/text_pipeline.dart
class TextPipeline {
  TextPipeline(this._rules);
  final List<FormattingRule> _rules;

  String apply(String bookId, String text) {
    var r = text;
    for (final rule in _rules.where((x) => x.bookId.isEmpty && x.isEnabled)) {
      r = _applyOne(rule, r);
    }
    for (final rule in _rules.where((x) => x.bookId == bookId && x.isEnabled)) {
      r = _applyOne(rule, r);
    }
    return r;
  }

  String _applyOne(FormattingRule rule, String input) {
    final match = unescapeControlChars(rule.match);
    final repl = unescapeControlChars(rule.replacement);
    if (!rule.isRegex) return input.replaceAll(match, repl);
    try {
      // 上游是 findAll + 字符串 replace，重复命中会出问题；Dart 用 replaceAllMapped 更正确
      return input.replaceAllMapped(RegExp(match), (m) {
        var out = repl;
        for (var i = 0; i <= m.groupCount; i++) {
          out = out.replaceAll('\$$i', m.group(i) ?? '');
        }
        return out;
      });
    } on FormatException {
      return input;                          // 单条非法正则不影响其它规则
    }
  }

  static String unescapeControlChars(String s) => s
      .replaceAll(r'\n', '\n').replaceAll(r'\t', '\t').replaceAll(r'\r', '\r')
      .replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
}
```

- 新增表 `formatting_rules(id INTEGER PRIMARY KEY AUTOINCREMENT, book_id TEXT NOT NULL DEFAULT '',
  name TEXT, is_regex INTEGER, match TEXT, replacement TEXT, is_enabled INTEGER)`，DB version 1 → 2（走 `onUpgrade`）。
- 接入点（对齐上游覆盖面）：书名/作者/简介、章节名、段落文本（走 `ContentComponent.mapText`）。
- 规则编辑 UI 放在设置页，支持正则高亮/非法正则时禁用保存。
- 内置规则建议：去广告尾注、去 `{123}` 字数标记；**额外做上游没有的简繁互转**（`SimplifiedTraditionalProcessor`
  的思路：平行字串表 + `map`，用一个 `[简,繁]` 常量表即可，23KB 级别）。

> 风险提示：规则在渲染期生效意味着**分页缓存 key 必须把「规则指纹」算进 styleSig**，
> 否则改规则后命中旧分页结果。上游没做这件事（它没有预分页），我们做预分页时必须补上。

---

## 3. P0 —— 分页缓存与内容哈希锚点

### 上游做法

上游**不做预分页**，而是用 `SubcomposeLayout` **渲染即测量**的增量分页（`FlipPageContentComponent.kt`）：

1. 每页是一个 `FlipPage(seed, displayed, resolved)`，初始把所有组件放进一页 seed；
2. `PageLayout` 用 `SubcomposeLayout` 逐个 measure 组件，发现放不下就回报 `PageMeasurement(overflowIndex, ...)`；
3. 溢出组件若实现 `Divisible` 就 `split(height, width)` 切成片段，prefix 留在本页，余下成为下一页 seed；
4. 循环直到所有页 `resolved`。

`ParagraphComponentData.split` 的做法：`TextMeasurer.measure(constraints(maxWidth = width))` →
`layout.getLineBottom(i) > height` 找最后一个容纳得下的行 → 按**字符偏移**切 `textNodes`（带样式一起切）。

缓存（`ChapterMeasurementWindow`）：

```kotlin
internal data class PaginationCacheKey(
    val chapterId: String, val contentSignature: Int, val styleSignature: Int,
    val width: Int, val height: Int,
)
// LinkedHashMap accessOrder=true，只留 3 条
val contentSignature = components.fold(1) { hash, c -> 31 * hash + c.hashCode() }
val styleSignature = 31 * readerStyle.hashCode() + baseStyle.hashCode()
```

测量尺寸变化时（横竖屏/分屏）不是从头开始，而是记录当前位置的哈希、重置、按哈希恢复。

锚点（这是最值得抄的一点）：

```kotlin
internal data class AnchoredComponent(
    val componentHash: Int,     // 组件级锚点
    val fragmentHash: Int,      // 切片级锚点（split 后每片自己的 hashCode）
    val data: AbstractContentComponentData,
)
```

恢复顺序：先 `fragmentPageIndex[fragmentHash]`，查不到退回 `componentPageIndex[componentHash]`（L638 的 `?:`）。
另外持久化一条 `reader.reading_location.<bookId>.<chapterId>` = Int（`user_data`），
作为**跨进程的 fragment 级锚点**。页码只存在内存里 —— 这就是它重排版不丢位置的原因。

### 我们的现状

`lib/core/pagination/paginator.dart` 是**纯函数预分页**：`TextPainter.layout` + `computeLineMetrics`
+ `getLineBoundary` 逐行切，输出 `List<ReaderPage>`；有标题 keep-with-next、孤行控制、行首缩进安全。
`lib/state/reader_controller.dart` 的 `repaginate()` 用 `findPageForAnchor(pages, paraIdx, lineIdx)` 恢复。

**我们的方案在可测试性和"页码确定"上优于上游**（`PageView` itemCount 固定、进度条可精确、纯函数可单测）。
不要为了抄上游而改成 SubcomposeLayout —— Compose 的 SubcomposeLayout 在 Flutter 没有等价物，
且它换来的是"页数未知、进度条只能估算、状态机复杂到需要 300 行场景测试兜底"。

### 落地方案（取上游两点，不改我们的分页算法）

1. **给分页结果加内容签名缓存**（替代当前无缓存或粗粒度缓存）：

```dart
// lib/core/pagination/pagination_cache.dart
class PaginationKey {
  const PaginationKey({required this.bookId, required this.chapterId, required this.contentSig,
      required this.styleSig, required this.width, required this.height, required this.rulesSig});
  // contentSig: 组件哈希折叠      styleSig: 排版参数指纹      rulesSig: 文本规则指纹（见 P0-2）
  @override int get hashCode => Object.hash(bookId, chapterId, contentSig, styleSig, width, height, rulesSig);
  @override bool operator ==(Object o) => o is PaginationKey && o.hashCode == hashCode;
}

class PaginationCache {                       // LinkedHashMap accessOrder 的 Dart 等价：手动 LRU
  final int capacity;                          // 上游 3，我们建议 6（相邻章节预排）
  final _entries = <PaginationKey, List<ReaderPage>>{};
  List<ReaderPage>? get(PaginationKey k) { final v = _entries.remove(k); if (v != null) _entries[k] = v; return v; }
  void put(PaginationKey k, List<ReaderPage> v) {
    _entries[k] = v;
    while (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }
}
```

2. **锚点从"纯索引"升级为"内容哈希 + 索引回退"**：

```dart
// 写入：page 首行对应的组件哈希
int anchorHashOf(ContentComponent c) => Object.hash(c.id, _textOf(c));
// 读取：先按哈希找页，找不到再按 (paragraphIndex, lineIndex) 找
int findPageForAnchor(List<ReaderPage> pages, {required int hash, required int paragraphIndex, required int lineIndex}) {
  for (final page in pages) { if (page.lines.isNotEmpty && page.lines.first.anchorHash == hash) return page.index; }
  return _findPageByIndex(pages, paragraphIndex, lineIndex);   // 现有逻辑
}
```

收益：用户切换「净化规则」或上游内容修正导致段落边界变化时，索引锚点会漂移，哈希锚点能落回同一段文字。

3. **相邻章节预排**：上游 `preloadChapterContent(prev/next)` 的思路，我们改成
`unawaited(_paginateAdjacent())` 在空闲时预排下一章，并把结果放进 `PaginationCache`（容量 6）——
翻到下一章时零计算。这直接服务 M5「滚动流畅度」。

涉及文件：`lib/core/pagination/paginator.dart`、`lib/core/pagination/page_line.dart`（加 `anchorHash`）、
`lib/data/repositories/reader_repository.dart`、`lib/state/reader_controller.dart`。

---

## 4. P0 —— 行为测试框架与可观测性钩子（直接服务 M5）

这是本项目 M5「真机联调：分页精度、滚动流畅度、导入边界」最缺的东西。
上游把 `:benchmark` 做成了**场景化 UI 行为测试框架**，不是性能跑分。

### 上游做法

**（a）框架层** `benchmark/framework/BenchmarkTestCase.kt`（430 行）：

```kotlin
@Before fun prepareDeterministicAppState() {
    device.pressHome()
    shell("pm clear $TARGET_PACKAGE")                     // 每次测试清库
    shell("cmd locale set-app-locales $TARGET_PACKAGE --user 0 --locales en-US")
    fixtureAction("SEED", "seed=SUCCEEDED")               // 用广播塞入固定测试书
}
```

配套 API：`openBook(title)` / `scrollToText` / `tapScrolledText` / `tapClickable`（沿父链找可点击节点）/
`setSliderForText`（拖滑块到指定比例）/ `assertSwitchForText` / `awaitUserData(path, expected)` /
`waitUntil(msg, timeout, interval) { cond }` / `averageScreenColor(Rect)`（截图像素均值，用于断言主题色生效）。

**（b）ReaderTestCase.kt**（290 行）—— 阅读器专用探针，含两个关键技巧：

```kotlin
// 技巧 1：把分页器内部状态挂到无障碍节点上，测试直接读
protected fun flipState(): String =
    device.findObjects(By.desc(Pattern.compile("flip-state-.*")))
        .mapNotNull { it.contentDescription }.firstOrNull() ?: "missing"

protected fun waitForPagerReady(timeout: Long = 15_000L) = waitUntil("pager did not paginate") {
    val s = flipState()
    Regex("count=(\\d+)").find(s)?.groupValues?.get(1)?.toIntOrNull() ?: 0 >= 2 &&
        s.contains("animating=false") && s.contains("direction=0")
}
// flip-state-... 节点的 contentDescription 形如 "count=12 animating=false direction=0 ..."

// 技巧 2：用资源名做稳定测试 ID，-pending 后缀表示"页还没解析完"
protected fun flipPage(): String = /* By.res(".*flip-page-.*")，取不以 -pending 结尾的那个 */

// 技巧 3：通过广播读**已持久化**的进度，而不是读 UI
protected fun savedProgress(): Float = Regex("progress=([0-9.-]+)")
    .find(shell("am broadcast -W -n $TARGET_PACKAGE/.benchmark.BenchmarkFixtureReceiver -a ...REPORT_PROGRESS"))
    ?.groupValues?.get(1)?.toFloatOrNull() ?: error("Progress missing")
```

**（c）场景层** `book/PageTurnReliabilityScenarios.kt` —— 7 个测试，全部是"把状态机往死里怼"：

| 场景 | 手法 |
| --- | --- |
| 动画翻页跨章双向 | `turnUntilChapter(2)` → 断言第 2 章起始标记可见 → 反向回第 1 章 |
| 边界幂等 | `reachBoundary(back)` 后再滑 3 次，断言 `flipPage()` 不变 |
| 快速动画滑动恢复 | 连滑 24 次（`steps=2, settleMs=25`）→ 等 idle → 断言停在第 2 章 |
| 无动画模式边界可交互 | 关动画后跨章往返，断言回到同一页 |
| 快速点击跨章恢复 | 连点 24 次（间隔 20ms） |
| 快速点击跨 8 章 | 先 `fixtureAction("EXTEND_RAPID_CHAPTER_CHAIN")` 造 10+ 章，连点 **320 次** |
| 音量键到书末不锁死 | 连按 24 次音量键，断言回到前台且能反向翻页 |

注意最后两条：**上游是在测自己真实存在的 bug**（书末锁死、快速输入丢状态）。
我们 `test/zz_hang_test.dart`、`test/zz_reader_jump_test.dart` 追的是同一类问题。

### 落地方案

```dart
// integration_test/harness/reader_harness.dart
class ReaderHarness {
  ReaderHarness(this.tester);
  final WidgetTester tester;

  Future<void> seed() async { /* 真机: 通过 debug channel 清库并写入 fixture 书 */ }
  Future<void> openBook(String title) async {
    await tester.tap(find.text('书架')); await tester.pumpAndSettle();
    await tester.tap(find.text(title)); await tester.pumpAndSettle();
  }
  Future<void> swipePage({required bool forward, int steps = 4}) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final y = size.height / 2;
    final from = forward ? size.width * 5 / 6 : size.width / 6;
    final to   = forward ? size.width / 6     : size.width * 5 / 6;
    await tester.flingFrom(Offset(from, y), Offset(to - from, 0), 800);
    await tester.pumpAndSettle();
  }
  Future<String> pagerState() async => await _readSemantics('pager-state');
  Future<void> waitForPagerReady({Duration timeout = const Duration(seconds: 15)}) async { /* 轮询 count>=2 && !busy */ }
  Future<double> savedProgress() async => await _debugChannel('reportProgress');   // 读数据库，不读 UI
}
```

**要在产品代码里加的三个钩子**（debug-only，用 `kDebugMode` 包住，不进 release）：

1. 分页器状态语义节点：在 `reader_screen.dart` 里放一个零尺寸 `Semantics`，
   `label` 形如 `'pager-state count=$pageCount current=$pageIndex busy=$isRepaginating chapter=$chapterIndex'`。
   这是上游 `flip-state-*` 的等价物，是本清单里**性价比最高**的一处改动——它让"分页对不对"从主观观察变成可断言。
2. 页面标识：每个页项包一层 `Key('page-$chapterIndex-$pageIndex')`，
   行级用 `Key('line-$paragraphIndex-$lineIndex-$anchorHash')`。
3. debug 通道：`MethodChannel('novel_reader/debug')` 暴露 `reportProgress` / `reportUserSetting(path)` /
   `seedFixture`，只在 debug 构建注册。

场景清单（照抄上游的对抗强度，映射到我们的分层）：

- `paginator` 层（纯函数单测，无需真机）：极端排版参数（字号 80%/160% × 行距 1.4/2.4）、
  超长无标点段落、只有标题没有正文的章、空章、单字符段落。
- `integration_test` 层：连续快滑 30 次不丢页；书末/书首边界幂等；跨章往返 3 轮；
  改字号后锚点不丢（对应上游 `ReaderAppearanceBehaviorScenarios`）；
  滚动模式快速滚动后进度写入节流正确；导入超限文件被拒（对应我们的 100MB 上限）。

---

## 5. P1 —— EPUB 导出

上游单独一个纯 JVM 模块 `:epub`（17 个文件，仅依赖 dom4j），App 侧唯一调用点在
`data/work/ExportBookToEPUBWork.kt`；章节内容通过 `AbstractContentComponentData.toHtmlElement()` 直接产出 XHTML。
**这正是 P0-1 组件模型的回报：导出不需要第二套渲染代码。**

必须照抄的硬约束：

```dart
// lib/epub/zip_packer.dart —— mimetype 必须首个条目且 STORED（不压缩）
final mimetype = utf8.encode('application/epub+zip');
// archive 包各版本 API 名不同，做一层适配，务必确认 compress:false 真的生效
ArchiveFile _stored(String name, List<int> bytes) =>
    ArchiveFile.bytes(name, bytes, compress: false);   // 旧版: ArchiveFile.noCompress(name, bytes)
```

固定条目顺序：`mimetype` → `META-INF/container.xml` → `EPUB/content.opf` → `EPUB/nav.xhtml`
→ `EPUB/toc.ncx` → `EPUB/*.xhtml` → `EPUB/style/main.css` → `EPUB/image/*`。

**上游缺 CSS，我们必须补上**（否则阅读器端丑且我们解析器的缩进信息会丢失）：

```css
p { text-indent: 2em; margin: 0.3em 0; line-height: 1.6; }
h1, h2, h3 { text-align: center; margin: 1em 0 0.6em; }
blockquote { margin: 0.6em 2em; border-left: 3px solid #888; padding-left: 0.8em; }
pre { font-family: monospace; background: #f5f5f5; padding: 0.6em; }
```

XHTML 转义（顺序敏感，`&` 必须最先）：

```dart
String escapeXml(String s) => s
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
```

再删非法码点（对齐上游 `sanitizeXmlSimple`）：`[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]`、
`\uFFFE\uFFFF`、孤立 surrogate；保留 `\t\n\r`。

建议文件布局：`lib/epub/{epub_builder.dart, epub_toc.dart, xhtml_writer.dart, zip_packer.dart, xml_escape.dart, epub_css.dart}`。
公开面（对齐上游的窄接口）：

```dart
class EpubBuilder {
  String title = '', author = '', description = '', publisher = '', language = 'zh-Hans';
  DateTime? modifiedUtc;
  Uint8List? coverBytes;                      // 需要 JPEG/PNG
  final List<TocNode> toc = [];
  final List<ChapterDoc> _docs = [];
  void chapter(String title, List<ContentComponent> components, {List<TocNode> children = const []});
  Epub build();                               // 校验：title/modified 必填、res key == href 强一致
}
```

**相对上游的修正清单**（上游的坑，别抄）：

- ❌ 章节 id 用 `hashCode()`（上游 `chapter_-1234567`，每次导出都变）→ ✅ `chapter_%04d`（章节序号）或 `ch_<bookId>_<idx>`
- ❌ `dcterms:modified` 用本地时间贴字面 `Z` → ✅ `DateTime.now().toUtc().toIso8601String()` 截到秒
- ❌ `dc:identifier` 用书名 → ✅ `const Uuid().v4()`（项目已有 `uuid` 依赖）
- ❌ `dc:language` 用 `Locale.toString()` → ✅ 真 BCP-47（`zh-Hans`）
- ❌ 图片 media-type 硬编码 `image/jpeg` → ✅ 按扩展名映射
- ❌ 章节 `<head>` 为空、无 `<title>`（epubcheck 告警）→ ✅ 每章写 `<title>` + `<link rel="stylesheet">`
- ❌ `includeImages` 参数一路传递却从未使用（勾了没用）→ ✅ 真实现
- ❌ 全内存构建（大书 OOM 风险）→ ✅ 逐章写、或限制单次导出章数并给进度

---

## 6. P1 —— 双进度模型

上游 `UserReadingDataEntity` 存**两个 map**（`current_chapter_reading_progress_map` /
`max_chapter_reading_progress_map`，CBOR 编码成 BLOB），语义：

- `current`：当前阅读位置，用于恢复
- `max`：只增不减（`coerceAtLeast`），用于判定"已读/读完"

全书进度不需要遍历目录：

```kotlin
readingProgress = maxChapterReadingProgressMap.values.sum() / total   // total = 全书章节数
if (readingData.readingProgress >= 1f) statsRepository.markBookFinished(bookId)
```

我们有 `progress(book_id, chapter_index, paragraph_index, line_index, percent, updated_at)` 单行，
`percent` 由 `reader_controller.bookPercent` 现算。问题：`percent` 用「章 + 页」估算，
换字号后页数变 → `percent` 跳变。

落地方案：新增 `chapter_progress(book_id, chapter_index, current REAL, max REAL, anchor_hash INTEGER,
PRIMARY KEY(book_id, chapter_index))`，`books.book_percent` 用 `SELECT SUM(max)/COUNT(*)` 维护。
`max` 只增保证书架上的百分比不会因为往回翻而回退。

---

## 7. P1 —— 设置存储：点分路径 + 类型列 + 读取端默认值

上游 `user_data(path PK, group, type, value)`，路径用密封层级集中定义（`UserDataPath.kt`）：

```kotlin
sealed class UserDataPath(name: String, parent: UserDataPath?) {
    val path = if (parent == null) name else "${parent.path}.$name"
    object Reader : UserDataPath("reader", null) { object FontSize : UserDataPath("font_size", Reader) }
}
```

关键决策：**默认值不在存储层，而在读取端**（`getOrDefault(default)` / `getFlowWithDefault(default)`）。
缺省即"未设置"，于是**新增设置项零迁移**。

我们目前是 `settings(id=0, payload)` 单行 JSON：加字段要动 `ReaderSettings.fromJson` 的容错，
且整块读写、无法只订阅某一项。

落地方案（保留单行 JSON 做兼容，新增 kv 表）：

```sql
CREATE TABLE settings_kv (
  path  TEXT PRIMARY KEY,   -- 'reader.font_size'
  grp   TEXT,               -- 'reader'
  type  TEXT NOT NULL,      -- 'string'|'int'|'double'|'bool'
  value TEXT NOT NULL
);
```

```dart
extension type const SettingPath(String path) {}
class Setting<T> {
  Setting(this._db, this.path, this._decode, this._encode);
  Future<T> get(T fallback) async { /* 无行 → fallback */ }
  Future<void> set(T v) async { /* upsert */ }
  Stream<T> watch(T fallback) { /* sqflite 没有 Room 的 Flow，用自建 StreamController + 写入后 notify */ }
}
```

顺手修掉上游两个 bug：`BooleanUserData.set` 把 `type` 写成 `"Float"`；
`StringListUserData` 用逗号 CSV（含逗号的字符串会坏）→ 我们用 `jsonEncode(list)`。

---

## 8. P1/P2 —— 面向 M6 的在线数据源（若要做）

上游的**接口形状**值得抄，**插件实现方式不值得抄**（Android APK 插件 + `PathClassLoader` 反射 + Hilt，
在 Flutter 里既不必要也不可行；其 JS 变体只有测试宿主、没有产品代码，是半成品）。

值得抄的形状：

```dart
abstract class BookSource {
  String get id; String get name;
  Map<String, String> get headers;            // UA / Referer / Cookie 由源自己声明
  String get encoding;                        // 显式声明（'gb18030' 等），不要依赖响应头
  Future<BookInfo> bookInfo(String bookId);
  Future<List<Volume>> volumes(String bookId);
  Future<ChapterContent> chapterContent(String chapterId, String bookId);
  Future<ExplorePage> explore(String pageId, {Map<String, String> filters = const {}, int page = 1});
  Stream<SearchEvent> search(String typeId, String keyword);
}
```

- **本地优先双发射**（上游 `BookRepository`）：先 emit 本地缓存的结果，再发网络请求，成功则**写穿**本地；
  网络失败仍保留本地发射。这是"离线可读"的最小实现。
- **typed error 而非异常**：`class SourceError { final String title, message; }`，不让异常穿透到 UI。
- **显式编码**：dio 用 `ResponseType.bytes` 拿 bytes，再按源声明的 encoding 解码
  （上游踩过 `bodyAsText` 的 charset 在响应头声明时不生效的坑）。
- **镜像 failover**：`hosts = [a, b, c]`，`Future.any` 竞速成功后取消其余。
- **请求合并 + TTL 缓存**：`_inflight[key] ??= _fetch()`。
- **按异常类型精确重试**：只对 `SocketException`/`TimeoutException` 指数退避重试 3 次，不要"全失败重试"。

**不要抄**：全局单源 + 切源清库 + `restart(appContext)`；把 Compose/Flow 写进数据源接口
（上游 `CustomExplorePageProvider.Content` 是个 `@Composable`）；缓存读用内容 key、写用源 id key
（上游 `ProxyCachedWebBookDataSource` 命中率为 0 的真实 bug）；硬编码第三方站点 cookie（含真实凭据）；
`runBlocking`；`delay(5.seconds)` 固定节流。

### 8.1 声明式源 manifest（替代上游的 APK 插件）

上游插件 = 完整 Android APK（改后缀 `.apk.lnrp`），靠 `@Plugin` 注解 + KSP 自动生成的 AndroidManifest
`meta-data` 描述自己，运行时用 `PathClassLoader` 加载、按构造器参数类型反射注入依赖
（`PluginInjector.provide` 三级兜底：静态 `INSTANCE` → 无参构造 → 参数类型全部命中的构造器）。
**这套机制在 Flutter 完全不可用**（Dart AOT 无动态类加载），但它想解决的问题是真的，用 manifest + 规则引擎替代：

```json
{
  "id": "example.com.src", "name": "示例源", "author": "someone", "description": "…",
  "apiVersion": 4, "versionCode": 12, "versionName": "1.2.0", "minAppVersion": "1.0.0",
  "type": "json", "baseUrl": "https://ex.com", "charset": "gb18030",
  "headers": {"User-Agent": "…", "Referer": "{{baseUrl}}"},
  "capabilities": ["search", "explore", "bookInfo", "volumes", "chapter"],
  "permissions": ["network", "cookies", "storage"],
  "cache": {"maxCountEachType": 10, "timeoutMs": 30000}, "permits": 8,
  "update": {"url": "https://store.ex.com/v1/plugin/{id}"},
  "rules": {
    "bookInfo": {"path": "/book/{id}", "title": "#info h1", "author": "#info .author", "cover": "img@src"},
    "volumes":  {"path": "/book/{id}", "items": ".volume", "chapters": "li a"},
    "chapter":  {"path": "/read/{chapterId}", "content": "#content p", "next": "#next@href"},
    "search":   {"path": "/search?q={q}&page={page}", "list": ".book-item", "title": "h3 a", "id": "a@href"},
    "explore":  [{"id":"top","title":"排行","path":"/top{{extra}}","list":".book-item",
                  "filters":[{"type":"single","key":"sort","choices":{"默认":"","热度":"&v=1"}}]}]
  }
}
```

三个可移植的机制：

1. **分组式 API 兼容**（`ApiCompat.groups = [{1}, {2,3}, {4}]`）：跨组完全不兼容，组内只允许 `sourceApi <= hostApi`。
   比"语义化版本比较"更简单可预测，用于安装前校验 + 启动加载过滤 + UI 开关禁用。

```dart
const _groups = [{1}, {2, 3}, {4}];
bool isSupported(int sourceApi, int hostApi) {
  final gh = _groups.indexWhere((s) => s.contains(hostApi));
  final gp = _groups.indexWhere((s) => s.contains(sourceApi));
  return gh >= 0 && gp >= 0 && gh == gp && sourceApi <= hostApi;
}
```

2. **原子安装 + 保留 data/**（`lock` 文件 + 启动跳过，而非目录快照）：
   `parse → clean(若 lock 或已加载) → stage(解包到临时目录) → 写 manifest → 建 lock → swap(保留 data/) → 删 lock → reload`。
   崩溃在 swap 之前的源，重启时因 lock 存在而既不加载也不列出；重装即可恢复，`data/` 始终保留。

```
{appSupport}/sources/<id>/{manifest.json, rules.json, data/, cache/, lock}
```

3. **能力门控**：`capabilities` 声明本源支持哪些入口，UI 据此隐藏"探索/搜索"页签，而不是调用了才报错。

安全注记（上游的教训，我们别重犯）：上游宿主**完全信任**插件，代码同进程同权限、无沙箱
（`PluginClassLoader` 只对 `kotlin.`/`androidx.`/`api.` 前缀委派父加载器，其余类先本地加载，等价于任意代码执行）；
签名比对**只在覆盖升级时**执行，首次安装未签名也放行；`GET_PERMISSIONS` 查而不验；
`usesCleartextTraffic=true`；商店 base URL 的"混淆"（url-safe base64 + Inflater）可逆，不是密钥保护；
`extractAssetFromApk` 用 `resolve(entry.name.removePrefix("assets/"))` 落盘，**恶意 zip entry 可路径穿越**。
我们若做远程源包导入：manifest 必须显式校验、解包必须做路径规范化（`p.normalize` 后断言仍在目标目录内）、
可选 manifest 内 Ed25519 签名 + 内容哈希。

---

## 9. P2 —— 其余可选项

### 9.1 阅读统计

上游按 `(book_id, date)` 记 `reads / seconds / is_finished / is_favorited / first_seen / last_seen`，
另有一张 `daily_count(date, time_count BLOB)` —— `time_count` 是**自制位图**：
`BitSet(144)`，每小时 6 bit（24 × 6），每格 0–60 分钟，序列化恰好 **18 字节**。
写入侧：前台每秒 `+1`，退出时 `-1` 抵消；累计满 60 秒才落盘一次（`bookReadTimeBuffer`）。
聚合契约：`getBookRecords(start,end)` / `getDailyCounts(start,end)` / `getTotalReadingSummary()`。

落地建议：先做「按书+按天」两张表，日期用 `int`（`yyyyMMdd`）。18 字节位图是巧妙但非必要，
除非要做年度热力图 —— 要做的话，Dart 侧用 `Uint8List(18)` 直接实现同一布局即可。

⚠️ 上游这块有真实瑕疵：`ReaderScreen.kt` 里跑了**两个并行计时循环**
（一个 60 秒 flush，一个每秒 `+1` 且 pause 时 `-1` 抵消）。我们用单一定时器 +
按 `DateTime` 差值 flush，避免同类问题。

### 9.2 存储占用管理

`data/storage/StorageUsageRepository.kt`：用 SQL 的 `length(cast(col as blob))` 在**不读内容**的前提下
估算每章体积（`StorageStatsDao.getChapterInformationBytes/getChapterContentBytes`），
按书聚合出 `BookStorageUsage(bookInformationBytes, volumeBytes, chapterInformationBytes, chapterContentBytes)`，
并区分 `orphanChapterInfoBytes` / `orphanChapterContentBytes`（可安全清理的孤儿）。
快照存进 user_data 避免每次重算。

对我们的意义：`content.jsonl` 是按书一个文件，用 `File.length()` 更简单；
但"**孤儿数据**"这个视角值得抄 —— 删书时若中途失败会残留正文文件与 `chapters` 行，
应提供 `审计并清理孤儿` 的入口。

### 9.3 后台任务 + 进度上报

上游 `data/work/`：`CacheBookWork`（逐章缓存整本）、`ExportBookToEPUBWork`（导出）、
`ImportDataWork`/`ExportDataWork`（数据备份）、`CheckUpdateWork`。
统一用 `DownloadItem(DownloadType, bookId, title)` + `DownloadProgressRepository` 暴露进度，
WorkManager 保证可重建。

对我们：不需要 WorkManager，但需要「**长任务 → 进度 → 可取消**」这个统一抽象。
建议 `lib/services/tasks/` 加 `ImportTaskRegistry`：导入/导出/整本下载都注册成 task，
带 `progress` / `cancel()` / 通知栏显示（`flutter_local_notifications`），
解决当前导入过程无进度、无法中断的问题。

### 9.4 阅读器 UX 细节（低成本高体感）

- **沉浸式 + 返回拦截三档**：`backBlockMode = none | double_press | fully_blocked`，
  双击返回时弹 Snackbar「再按一次退出」（1.5 秒窗口）。
- **音量键翻页**（`isUsingVolumeKeyFlip`）与连续翻页间隔，物理键在冬天戴手套时非常好用。
- **点击分区翻页**（`isUsingClickFlipPage`）+ 屏幕中央呼出菜单。
- **常亮** `FLAG_KEEP_SCREEN_ON` 开关；**自动内边距**（`autoPadding`，按 `WindowInsets.safeContent`
  自动算上下留白）+ 手动四边留白。
- **背景图**（亮/暗各一张，`fixed | loop` 两种显示模式）+ 前景文字色可调。
- **阅读中指示器**：电量、时间、章节标题、本章进度的独立开关。
- **翻页动画可选**（含"无动画"，这是快速点击场景的基础）。

---

## 10. 明确不要借鉴的清单

| 上游做法 | 为什么不抄 | 我们的替代 |
| --- | --- | --- |
| Compose `SubcomposeLayout` 增量分页 | Flutter 无等价物；页数未知导致进度条只能估算；状态机需 300 行测试兜底 | 保留 `TextPainter` 预分页（可单测、页数确定），只借缓存与哈希锚点 |
| Android APK 插件 + `PathClassLoader` 反射 + KSP 自动清单 | Flutter 无此模型；上游 JS 变体没有产品代码 | 若做在线源：声明式 JSON 源 + 规则引擎 |
| Hilt `@Singleton` 全局注入 | Flutter 用 Provider/构造注入即可 | 现有 `main.dart` 装配保持 |
| 全局单源 + 切源清库 + `restart(appContext)` | 用户数据被迫隔离成多份快照，切源体验粗暴 | 书的 `source_id` 字段做隔离，不重启 |
| 11 个实体各写一个 `merge` | 只有云端同步才需要 | 一个 `upsertWithMerge(table, key, mergeFn)` 泛型工具 |
| 全内存构建 EPUB | 大书 OOM | 逐章写盘 / 限制单次导出 |
| `daily_count` 18 字节位图 | 只有年度热力图才值得 | 先 `int` 日聚合，需要再上 |
| `Result` 只取 `component1()` 导致错误退化为字符串 | 丢失错误语义 | 我们的 `SourceError{title,message}` 保留类型 |
| 硬编码第三方站点 cookie | 含真实凭据，且注定失效 | 由源定义声明，不含默认值 |
| 两套并行计时循环统计阅读时长 | 有减法抵消逻辑，易错 | 单定时器 + 时间差 flush |

---

## 11. 落地路线（对齐现有里程碑）

| 序 | 事项 | 对应文档 | 影响文件 | 预估 |
| --- | --- | --- | --- | --- |
| 1 | 分页状态语义钩子（`pager-state count=... busy=...`）| §4 | `lib/ui/pages/reader_screen.dart` | 0.5 天 |
| 2 | `integration_test` 测试框架 + 场景清单 | §4 | `integration_test/**`（新增） | 2 天 |
| 3 | 分页缓存（key 含 contentSig/styleSig/rulesSig）| §3 | `lib/core/pagination/*` | 1 天 |
| 4 | 内容组件模型 + jsonl v2 + 迁移 | §1 | `lib/core/content/*`、`lib/core/parsers/*` | 3 天 |
| 5 | 净化规则（表 + 管道 + 编辑 UI）| §2 | `lib/core/text/*`、`lib/data/*` | 2 天 |
| 6 | 双进度 + 章节进度表 | §6 | `lib/data/app_database.dart`、`lib/state/reader_controller.dart` | 1 天 |
| 7 | EPUB 导出（含 CSS、稳定 id、真转义）| §5 | `lib/epub/*`（新增）、`pubspec.yaml` 无需新依赖 | 3 天 |
| 8 | 设置 kv 化 + 类型化路径 | §7 | `lib/data/*`、`lib/state/settings_controller.dart` | 1.5 天 |
| 9 | 长任务注册表（导入/导出进度与取消）| §9.3 | `lib/services/tasks/*`（新增） | 2 天 |
| 10 | 阅读器 UX 细节打包（返回拦截/音量键/分区/常亮）| §9.4 | `lib/ui/pages/reader_screen.dart` | 1.5 天 |
| 11 | （M6）声明式在线数据源 | §8 | `lib/services/sources/*`（新增） | 5 天+ |

**依赖关系**：4 → 5（规则作用于组件）与 4 → 7（导出复用 `toXhtml`）；3 依赖 5 的规则指纹；1 是 2 的前置。

**许可证**：上游为 Apache-2.0。借鉴思路与接口形状无需署名，但若**直接复制代码片段**
（如 `ParagraphComponentData.split` 的测行逻辑、`Count` 的位图布局），
需在文件头保留版权声明与来源链接，并在 `NOTICE` 中列明。

---

## 附：本文结论的证据位置

| 结论 | 上游文件 |
| --- | --- |
| 内容组件抽象与容错 | `api/src/main/kotlin/io/nightfish/lightnovelreader/api/content/component/data/AbstractContentComponentData.kt`、`app/.../data/content/ContentComponentRepository.kt:42-58` |
| 段落切片 | `api/.../content/component/data/ParagraphComponentData.kt:89-150`、`.../Divisible.kt` |
| 文本规则 | `app/.../data/format/FormatRepository.kt:77-121,182-221`、`.../FormattingRule.kt` |
| 分页状态机与缓存 | `app/.../ui/book/reader/content/flip/FlipPageContentComponent.kt:445-590,870-929,946-1012` |
| 锚点恢复 | `.../flip/FlipPageContentViewModel.kt:48-77,155-190`、`.../reader/ReaderViewModel.kt:104-150` |
| 双进度 | `app/.../data/local/room/entity/UserReadingDataEntity.kt`、`local/room/converter/ChapterReadingProgressMapConverter.kt` |
| 设置存储 | `api/.../userdata/UserDataPath.kt`、`app/.../ui/book/reader/SettingState.kt` |
| 统计位图 | `app/.../data/statistics/Count.kt`、`.../StatsRepository.kt` |
| 存储占用 | `app/.../data/storage/StorageUsageRepository.kt` |
| EPUB 生成 | `epub/src/main/kotlin/io/nightfish/potatoepub/**`、`app/.../data/work/ExportBookToEPUBWork.kt` |
| 测试框架 | `benchmark/src/main/kotlin/.../framework/BenchmarkTestCase.kt`、`.../framework/ReaderTestCase.kt`、`.../book/PageTurnReliabilityScenarios.kt` |
| 数据源接口 | `api/.../web/WebBookDataSource.kt`、`api/.../book/BookRepositoryApi.kt`、`app/.../defaultplugin/wenku8/**` |
