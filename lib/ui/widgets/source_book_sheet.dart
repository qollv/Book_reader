import 'package:flutter/material.dart';

import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/source_book.dart';
import 'package:novel_reader/state/explore_controller.dart';
import 'package:novel_reader/ui/widgets/book_cover_image.dart';

/// 在线书详情面板：先用手上的列表数据渲染，再补详情与目录。
///
/// 交互取舍：**先给内容再补细节**。列表项已经有标题/作者/封面，
/// 立刻渲染它，别让用户对着转圈等详情页；详情回来后再补简介、标签、章数。
///
/// 依赖取舍：面板只接收它真正需要的三个回调，而不是整个 ExploreController。
/// 这样它既能在生产里被一行 `show()` 装好，也能在测试里用假回调直接渲染，
/// 不必为了看它一眼就去准备数据库与网络。
class SourceBookSheet extends StatefulWidget {
  const SourceBookSheet({
    super.key,
    required this.book,
    required this.loadShelfState,
    required this.loadDetail,
    required this.importBook,
    required this.onOpenBook,
  });

  final SourceBook book;

  /// 查这本书是否已在书架（命中时按钮变成「更新本地副本」并出现「阅读」）。
  final Future<Book?> Function() loadShelfState;

  /// 拉详情与目录，用于补简介、标签与章数。
  final Future<SourceBookDetail> Function() loadDetail;

  /// 整本抓取并入库。
  final Future<Book> Function(
    void Function(int fetched, int total, String title)? onProgress,
    Future<bool> Function()? shouldContinue,
  ) importBook;

  /// 导入成功后由页面负责跳转到阅读器（面板不该管导航）。
  final void Function(Book book) onOpenBook;

  static Future<void> show(
    BuildContext context, {
    required SourceBook book,
    required ExploreController explore,
    required void Function(Book book) onOpenBook,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SourceBookSheet(
        book: book,
        loadShelfState: () => explore.findOnShelf(book),
        loadDetail: () => explore.loadDetail(book),
        importBook: (
          void Function(int fetched, int total, String title)? onProgress,
          Future<bool> Function()? shouldContinue,
        ) =>
            explore.importToShelf(
          book,
          onProgress: onProgress,
          shouldContinue: shouldContinue,
        ),
        onOpenBook: onOpenBook,
      ),
    );
  }

  @override
  State<SourceBookSheet> createState() => _SourceBookSheetState();
}

class _SourceBookSheetState extends State<SourceBookSheet> {
  SourceBookDetail? _detail;
  String? _detailError;
  bool _loadingDetail = true;

  bool _checkingShelf = true;
  Book? _onShelf;

  bool _importing = false;
  int _imported = 0;
  int _importTotal = 0;
  String _importTitle = '';
  bool _cancelRequested = false;
  String? _importError;

  @override
  void initState() {
    super.initState();
    _loadShelfState();
    _loadDetail();
  }

  Future<void> _loadShelfState() async {
    final Book? existing = await widget.loadShelfState();
    if (!mounted) {
      return;
    }
    setState(() {
      _onShelf = existing;
      _checkingShelf = false;
    });
  }

  Future<void> _loadDetail() async {
    try {
      final SourceBookDetail detail = await widget.loadDetail();
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _loadingDetail = false;
      });
    } on SourceError catch (e) {
      if (!mounted) {
        return;
      }
      // 详情失败不该让面板不可用：列表数据还在，仍可尝试导入
      setState(() {
        _detailError = e.message;
        _loadingDetail = false;
      });
    } on Object catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _detailError = '$e';
        _loadingDetail = false;
      });
    }
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _importError = null;
      _imported = 0;
      _importTotal = 0;
      _cancelRequested = false;
    });
    try {
      final Book book = await widget.importBook(
        (int fetched, int total, String title) {
          if (!mounted) {
            return;
          }
          setState(() {
            _imported = fetched;
            _importTotal = total;
            _importTitle = title;
          });
        },
        () async => !_cancelRequested,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      widget.onOpenBook(book);
    } on SourceError catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _importing = false;
        _importError = e.message;
      });
    } on Object catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _importing = false;
        _importError = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // 详情补全而不是替换：列表项可能握有详情页没有的标签/封面
    final SourceBook book = _detail == null
        ? widget.book
        : widget.book.merge(_detail!.book);
    final int? chapterCount = _detail?.chapters.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BookCoverImage(
                    title: book.title,
                    coverUrl: book.coverUrl,
                    width: 84,
                    height: 116,
                    fontSize: 32,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(book.title,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                          book.author.isEmpty ? '未知作者' : book.author,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        if (_loadingDetail)
                          Row(children: <Widget>[
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text('正在读取目录…', style: theme.textTheme.bodySmall),
                          ])
                        else if (chapterCount != null)
                          Text('共 $chapterCount 章', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        if (book.tags.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              for (final String tag in book.tags)
                                Chip(
                                  label: Text(tag, style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (book.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Text(book.description,
                    style: theme.textTheme.bodySmall, maxLines: 6, overflow: TextOverflow.ellipsis),
              ],
              if (_detailError != null) ...<Widget>[
                const SizedBox(height: 12),
                _Notice(
                  icon: Icons.warning_amber_rounded,
                  text: '详情读取失败：$_detailError\n仍可尝试直接导入。',
                ),
              ],
              if (_importError != null) ...<Widget>[
                const SizedBox(height: 12),
                _Notice(icon: Icons.error_outline, text: '导入失败：$_importError'),
              ],
              const SizedBox(height: 18),
              if (_importing) ...<Widget>[
                LinearProgressIndicator(
                  value: _importTotal == 0 ? null : _imported / _importTotal,
                ),
                const SizedBox(height: 8),
                Text(
                  _importTotal == 0
                      ? '正在抓取目录…'
                      : '正在抓取 $_imported/$_importTotal  $_importTitle',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _cancelRequested = true),
                    child: const Text('取消'),
                  ),
                ),
              ] else ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _checkingShelf ? null : _import,
                        icon: Icon(_onShelf == null ? Icons.download : Icons.refresh),
                        label: Text(
                          _onShelf == null
                              ? '加入书架并下载'
                              : '更新本地副本',
                        ),
                      ),
                    ),
                    if (_onShelf != null) ...<Widget>[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onOpenBook(_onShelf!);
                        },
                        icon: const Icon(Icons.menu_book),
                        label: const Text('阅读'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '下载完成后即为离线可读，正文存为本地排版文件，与本地导入的书完全一致。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
