import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/models/source_manifest.dart';
import 'package:novel_reader/services/source/source_registry.dart';
import 'package:novel_reader/state/explore_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/source_controller.dart';
import 'package:novel_reader/ui/pages/reader_screen.dart';
import 'package:novel_reader/ui/pages/source_manager_page.dart';
import 'package:novel_reader/ui/pages/source_search_page.dart';
import 'package:novel_reader/ui/widgets/book_cover_image.dart';
import 'package:novel_reader/ui/widgets/source_book_sheet.dart';

/// 探索页：按当前激活源声明的探索页生成 tab，支持过滤器与无限翻页。
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final Map<String, ScrollController> _scrollControllers = <String, ScrollController>{};
  String? _boundSourceId;

  @override
  void dispose() {
    for (final ScrollController controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  ScrollController _controllerFor(String ruleId) {
    return _scrollControllers.putIfAbsent(ruleId, () {
      final ScrollController controller = ScrollController();
      controller.addListener(() {
        if (!controller.hasClients) {
          return;
        }
        final double remaining =
            controller.position.maxScrollExtent - controller.position.pixels;
        if (remaining < 400) {
          // 触底前预取，滚到底时才加载会有明显空窗
          context.read<ExploreController>().loadMore(ruleId);
        }
      });
      return controller;
    });
  }

  void _syncActiveSource() {
    final SourceController sources = context.read<SourceController>();
    final ExploreController explore = context.read<ExploreController>();
    final String? active = sources.activeSourceId;
    if (active == _boundSourceId) {
      return;
    }
    _boundSourceId = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        explore.bindSource(active);
      }
    });
  }

  void _openBook(Book book) {
    context.read<ReaderController>().openBook(book.id);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ReaderScreen(),
    ));
  }

  Future<void> _pickSource() async {
    final SourceController sources = context.read<SourceController>();
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const ListTile(
                dense: true,
                title: Text('选择数据源', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              for (final SourceEntry entry in sources.usableEntries)
                ListTile(
                  title: Text(entry.name),
                  subtitle: Text(
                    SourceController.describeCapabilities(entry.manifest),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: sources.activeSourceId == entry.id
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, entry.id),
                ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('管理数据源'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const SourceManagerPage(),
                  ));
                },
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      sources.setActiveSource(picked);
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncActiveSource();

    final SourceController sources = context.watch<SourceController>();
    final ExploreController explore = context.watch<ExploreController>();

    if (sources.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: sources.hasUsableSource ? _pickSource : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  sources.activeEntry?.name ?? '探索',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sources.usableEntries.length > 1) ...<Widget>[
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          if (explore.canSearch)
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const SourceSearchPage(),
              )),
            ),
          IconButton(
            tooltip: '数据源管理',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const SourceManagerPage(),
            )),
          ),
        ],
      ),
      body: !sources.hasUsableSource
          ? _NoSourceGuide(
              onInstallSample: () async {
                final SourceInstallResult result =
                    await context.read<SourceController>().installSample();
                if (!context.mounted) {
                  return;
                }
                _showInstallResult(context, result);
              },
            )
          : explore.exploreRules.isEmpty
              ? _NoExploreGuide(onOpenSearch: explore.canSearch)
              : _ExploreTabs(
                  explore: explore,
                  controllerFor: _controllerFor,
                  onOpenBook: _openBook,
                ),
    );
  }

  static void _showInstallResult(BuildContext context, SourceInstallResult result) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        result.ok
            ? '${result.message}。示例源指向本地 fixture 站点，先运行 dart run tool/fixture_site.dart 再刷新。'
            : result.message,
      ),
      duration: const Duration(seconds: 6),
    ));
  }
}

/// 把 SourceEntry 展示成能力标签的辅助，已内联到调用处。
class _ExploreTabs extends StatelessWidget {
  const _ExploreTabs({
    required this.explore,
    required this.controllerFor,
    required this.onOpenBook,
  });

  final ExploreController explore;
  final ScrollController Function(String ruleId) controllerFor;
  final void Function(Book book) onOpenBook;

  @override
  Widget build(BuildContext context) {
    final List<SourceExploreRule> rules = explore.exploreRules;
    return DefaultTabController(
      length: rules.length,
      child: Column(
        children: <Widget>[
          // 哪怕只有一个探索页也把 tab 显示出来：用户需要知道自己看的是哪一档，
          // 否则多个源/多档切换时界面完全没有锚点
          TabBar(
            isScrollable: rules.length > 1,
            tabs: <Widget>[
              for (final SourceExploreRule rule in rules) Tab(text: rule.title),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final SourceExploreRule rule in rules)
                  _ExploreRow(
                    key: ValueKey<String>('explore-${rule.id}'),
                    rule: rule,
                    explore: explore,
                    scrollController: controllerFor(rule.id),
                    onOpenBook: onOpenBook,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreRow extends StatelessWidget {
  const _ExploreRow({
    super.key,
    required this.rule,
    required this.explore,
    required this.scrollController,
    required this.onOpenBook,
  });

  final SourceExploreRule rule;
  final ExploreController explore;
  final ScrollController scrollController;
  final void Function(Book book) onOpenBook;

  @override
  Widget build(BuildContext context) {
    final ExploreRowState state = explore.stateOf(rule.id);

    return Column(
      children: <Widget>[
        if (rule.list.filters.isNotEmpty)
          _FilterBar(rule: rule, state: state, explore: explore),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => explore.load(rule.id, refresh: true),
            child: state.isLoading && state.books.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.error != null && state.books.isEmpty
                    ? _ErrorState(
                        message: state.error!,
                        onRetry: () => explore.load(rule.id, refresh: true),
                      )
                    : state.isEmpty
                        ? _EmptyState(
                            text: '这一档没有内容',
                            onRetry: () => explore.load(rule.id, refresh: true),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: state.books.length + 1,
                            itemBuilder: (BuildContext context, int index) {
                              if (index == state.books.length) {
                                return _ListFooter(state: state);
                              }
                              final SourceBook book = state.books[index];
                              return _SourceBookTile(
                                book: book,
                                onTap: () => SourceBookSheet.show(
                                  context,
                                  book: book,
                                  explore: explore,
                                  onOpenBook: onOpenBook,
                                ),
                              );
                            },
                          ),
          ),
        ),
        if (state.error != null && state.books.isNotEmpty)
          MaterialBanner(
            content: Text('加载下一页失败：${state.error}', style: const TextStyle(fontSize: 12)),
            actions: <Widget>[
              TextButton(
                onPressed: () => explore.loadMore(rule.id),
                child: const Text('重试'),
              ),
            ],
          ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.rule, required this.state, required this.explore});

  final SourceExploreRule rule;
  final ExploreRowState state;
  final ExploreController explore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          for (final SourceFilterRule filter in rule.list.filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: _buildFilter(context, filter)),
            ),
        ],
      ),
    );
  }

  Widget _buildFilter(BuildContext context, SourceFilterRule filter) {
    switch (filter.type) {
      case SourceFilterType.single:
        final String current = state.filterChoices[filter.key] ?? filter.defaultChoice;
        // 选项多于 3 个时不塞进横向 chip，交给底部弹窗，避免挤成一团
        if (filter.choices.length > 3) {
          return ActionChip(
            avatar: const Icon(Icons.tune, size: 16),
            label: Text('${filter.title}：$current'),
            onPressed: () async {
              final String? picked = await showModalBottomSheet<String>(
                context: context,
                builder: (BuildContext sheetContext) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final String choice in filter.choices.keys)
                        ListTile(
                          title: Text(choice),
                          trailing: current == choice
                              ? const Icon(Icons.check, size: 18)
                              : null,
                          onTap: () => Navigator.pop(sheetContext, choice),
                        ),
                    ],
                  ),
                ),
              );
              if (picked != null) {
                await explore.setFilterChoice(rule.id, filter.key, picked);
              }
            },
          );
        }
        return Wrap(
          spacing: 6,
          children: <Widget>[
            for (final String choice in filter.choices.keys)
              ChoiceChip(
                label: Text(choice, style: const TextStyle(fontSize: 12)),
                selected: current == choice,
                onSelected: (_) => explore.setFilterChoice(rule.id, filter.key, choice),
              ),
          ],
        );

      case SourceFilterType.toggle:
        final bool current =
            state.filterToggles[filter.key] ?? (filter.defaultChoice == 'true');
        return FilterChip(
          label: Text(filter.title, style: const TextStyle(fontSize: 12)),
          selected: current,
          onSelected: (bool value) =>
              explore.setFilterToggle(rule.id, filter.key, value),
        );

      case SourceFilterType.slider:
        return _SliderFilter(
          filter: filter,
          value: state.filterSliders[filter.key] ?? filter.defaultValue,
          onCommitted: (double value) =>
              explore.setFilterSlider(rule.id, filter.key, value),
        );
    }
  }
}

/// 滑块过滤器。
///
/// 拖动过程只改本地值（跟手），**松手才**发请求——否则每移动一格都会打一次
/// 网络，手一抖就是十几次请求。
class _SliderFilter extends StatefulWidget {
  const _SliderFilter({
    required this.filter,
    required this.value,
    required this.onCommitted,
  });

  final SourceFilterRule filter;
  final double value;
  final Future<void> Function(double value) onCommitted;

  @override
  State<_SliderFilter> createState() => _SliderFilterState();
}

class _SliderFilterState extends State<_SliderFilter> {
  late double _draft = widget.value;

  @override
  void didUpdateWidget(covariant _SliderFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _draft = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('${widget.filter.title} ${_draft.round()}',
            style: const TextStyle(fontSize: 12)),
        SizedBox(
          width: 120,
          child: Slider(
            min: widget.filter.min,
            max: widget.filter.max,
            divisions: widget.filter.steps > 0 ? widget.filter.steps : null,
            value: _draft.clamp(widget.filter.min, widget.filter.max),
            onChanged: (double value) => setState(() => _draft = value),
            onChangeEnd: (double value) => widget.onCommitted(value),
          ),
        ),
      ],
    );
  }
}

class _SourceBookTile extends StatelessWidget {
  const _SourceBookTile({required this.book, required this.onTap});

  final SourceBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: BookCoverImage(
        title: book.title,
        coverUrl: book.coverUrl,
        width: 44,
        height: 60,
        fontSize: 20,
      ),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (book.author.isNotEmpty)
            Text(book.author, style: theme.textTheme.bodySmall),
          if (book.description.isNotEmpty)
            Text(
              book.description,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.state});

  final ExploreRowState state;

  @override
  Widget build(BuildContext context) {
    // 只有「正在加载下一页」时才转圈。
    // 之前这里在没有更多内容之前都常驻一个无限动画的指示器：
    // 视觉上永远在转，实际上多数时间什么都没发生；同时它会让任何
    // 等待界面静止的逻辑（pumpAndSettle / 无障碍朗读）永远等不到静止。
    if (state.reachedEnd) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('没有更多了', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }
    if (!state.isLoadingMore) {
      return const SizedBox(height: 24);
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _NoSourceGuide extends StatelessWidget {
  const _NoSourceGuide({required this.onInstallSample});

  final Future<void> Function() onInstallSample;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.explore_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 14),
            const Text('还没有可用的数据源', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              '数据源是一份 JSON 声明，描述怎么抓一本书的详情、目录与正文。\n'
              '本机自带一个示例源，安装后指向本地 fixture 站点，'
              '可以完整跑通探索、搜索、导入三件事。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => onInstallSample(),
              icon: const Icon(Icons.download),
              label: const Text('安装内置示例源'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const SourceManagerPage(),
              )),
              icon: const Icon(Icons.dns_outlined),
              label: const Text('打开数据源管理'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoExploreGuide extends StatelessWidget {
  const _NoExploreGuide({required this.onOpenSearch});

  final bool onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.travel_explore, size: 56, color: Colors.grey),
            const SizedBox(height: 14),
            const Text('这个源没有探索页', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              '它可能只支持搜索。用右上角的搜索按钮找书。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (onOpenSearch) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const SourceSearchPage(),
                )),
                icon: const Icon(Icons.search),
                label: const Text('去搜索'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: <Widget>[
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: <Widget>[
              const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(text),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('刷新')),
            ],
          ),
        ),
      ],
    );
  }
}
