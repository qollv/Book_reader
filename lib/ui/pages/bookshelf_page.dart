import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/services/sync/sync_service.dart';
import 'package:novel_reader/state/bookshelf_controller.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';
import 'package:novel_reader/ui/pages/reader_page.dart';
import 'package:novel_reader/ui/theme/reading_palettes.dart';
import 'package:novel_reader/ui/widgets/import_options_sheet.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  // 设备 ID 实际应首次生成后持久化，这里用固定值演示合并逻辑
  static const String _deviceId = 'device-local';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BookshelfController>().load();
      }
    });
  }

  Future<void> _importLocal() async {
    final BookshelfController controller = context.read<BookshelfController>();
    final Book? book = await controller.importLocal();
    if (!mounted) {
      return;
    }
    _showErrorIfAny(controller);
    if (book != null) {
      _openBook(book.id);
    }
  }

  Future<void> _importFromUrl(String url) async {
    final BookshelfController controller = context.read<BookshelfController>();
    final Book? book = await controller.importFromUrl(url);
    if (!mounted) {
      return;
    }
    _showErrorIfAny(controller);
    if (book != null) {
      _openBook(book.id);
    }
  }

  void _showErrorIfAny(BookshelfController controller) {
    final String? error = controller.importError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      controller.clearError();
    }
  }

  void _openBook(String bookId) {
    context.read<ReaderController>().openBook(bookId);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ReaderPage(),
    ));
  }

  Future<void> _sync() async {
    final ProgressSyncService service = context.read<ProgressSyncService>();
    final SyncReport report = await service.sync(_deviceId);
    if (!mounted) {
      return;
    }
    await context.read<BookshelfController>().load();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('同步完成：进度 ${report.pulledProgress}，书签 ${report.pulledBookmarks}，笔记 ${report.pulledNotes}'),
    ));
  }

  Future<void> _confirmDelete(BookshelfItem item) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除书籍'),
          content: Text('删除《${item.book.title}》将同时清除它的进度、书签和笔记，且不可恢复。'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
          ],
        );
      },
    );
    if (ok == true && mounted) {
      await context.read<BookshelfController>().deleteBook(item.book.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final BookshelfController controller = context.watch<BookshelfController>();
    final SettingsController settingsController = context.watch<SettingsController>();
    final ReadingPalette palette = ReadingPalette.all[settingsController.settings.paletteIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.sync), tooltip: '同步进度', onPressed: _sync),
        ],
      ),
      body: Stack(
        children: <Widget>[
          if (controller.items.isEmpty)
            const _EmptyShelf()
          else
            GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.62,
              ),
              itemCount: controller.items.length,
              itemBuilder: (BuildContext context, int index) {
                final BookshelfItem item = controller.items[index];
                return _BookCard(
                  item: item,
                  palette: palette,
                  onTap: () => _openBook(item.book.id),
                  onLongPress: () => _confirmDelete(item),
                );
              },
            ),
          if (controller.isImporting)
            _ImportingOverlay(fraction: controller.importFraction),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ImportOptionsSheet.show(
          context,
          onPickLocal: _importLocal,
          onImportUrl: _importFromUrl,
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 书架封面占位：书名首字 + 由书名哈希决定的固定色。
class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.item,
    required this.palette,
    required this.onTap,
    required this.onLongPress,
  });

  final BookshelfItem item;
  final ReadingPalette palette;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const List<Color> _coverColors = <Color>[
    Color(0xFF8D6E63),
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF9A9A),
    Color(0xFF9575CD),
    Color(0xFF4DB6AC),
  ];

  @override
  Widget build(BuildContext context) {
    final Book book = item.book;
    final int colorIndex = book.title.hashCode.abs() % _coverColors.length;
    final int percent = (item.percent * 100).round();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _coverColors[colorIndex],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                book.title.isEmpty ? '书' : book.title[0],
                style: const TextStyle(fontSize: 42, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: palette.text),
          ),
          const SizedBox(height: 2),
          Text(
            '${book.author.isEmpty ? '未知作者' : book.author} · 已读 $percent%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: palette.secondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.menu_book, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('书架还是空的', style: TextStyle(fontSize: 16, color: Colors.grey)),
          SizedBox(height: 4),
          Text('点右下角 + 导入 txt / md / docx', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ImportingOverlay extends StatelessWidget {
  const _ImportingOverlay({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('正在导入并排版...'),
                  if (fraction > 0) ...<Widget>[
                    const SizedBox(height: 8),
                    Text('${(fraction * 100).round()}%'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
