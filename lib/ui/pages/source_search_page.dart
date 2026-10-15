import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/models/source_manifest.dart';
import 'package:novel_reader/state/explore_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/ui/pages/reader_screen.dart';
import 'package:novel_reader/ui/widgets/book_cover_image.dart';
import 'package:novel_reader/ui/widgets/source_book_sheet.dart';

/// 搜索页：按当前源声明的搜索方式检索，结果可逐条追加（允许部分成功）。
class SourceSearchPage extends StatefulWidget {
  const SourceSearchPage({super.key});

  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  final TextEditingController _keyword = TextEditingController();

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  void _openBook(Book book) {
    context.read<ReaderController>().openBook(book.id);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ReaderScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ExploreController explore = context.watch<ExploreController>();
    final List<SourceSearchTypeRule> types = explore.searchTypes;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _keyword,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '输入关键词',
            border: InputBorder.none,
          ),
          onSubmitted: (String value) => explore.search(value),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => explore.search(_keyword.text),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (types.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final SourceSearchTypeRule type in types)
                      ChoiceChip(
                        label: Text(type.name, style: const TextStyle(fontSize: 12)),
                        selected: explore.searchTypeId == type.id,
                        onSelected: (_) => explore.setSearchType(type.id),
                      ),
                  ],
                ),
              ),
            ),
          if (explore.searchError != null)
            MaterialBanner(
              content: Text(
                explore.searchResults.isEmpty
                    ? '搜索失败：${explore.searchError}'
                    : '部分结果可能缺失：${explore.searchError}',
                style: const TextStyle(fontSize: 12),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => explore.search(_keyword.text),
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(child: _buildBody(explore)),
        ],
      ),
    );
  }

  Widget _buildBody(ExploreController explore) {
    if (explore.isSearching && explore.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (explore.lastKeyword.isEmpty) {
      return const _Hint(
        icon: Icons.search,
        title: '搜索这本书',
        detail: '支持源声明的多种搜索方式；结果逐条返回，先出先看。',
      );
    }
    if (explore.searchResults.isEmpty && explore.searchError == null) {
      return _Hint(
        icon: Icons.sentiment_dissatisfied,
        title: '没有找到「${explore.lastKeyword}」',
        detail: '换个关键词，或换一个数据源试试。',
      );
    }
    return ListView.builder(
      itemCount: explore.searchResults.length,
      itemBuilder: (BuildContext context, int index) {
        final SourceBook book = explore.searchResults[index];
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
          subtitle: book.author.isEmpty
              ? null
              : Text(book.author, style: Theme.of(context).textTheme.bodySmall),
          onTap: () => SourceBookSheet.show(
            context,
            book: book,
            explore: explore,
            onOpenBook: _openBook,
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(title),
            const SizedBox(height: 6),
            Text(detail,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
