import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';
import 'package:novel_reader/ui/pages/annotations_page.dart';
import 'package:novel_reader/ui/theme/reading_palettes.dart';
import 'package:novel_reader/ui/widgets/reader_settings_sheet.dart';

/// 阅读器页面：分页渲染 + 点按呼出菜单 + 章节/进度/书签/笔记入口。
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final PageController _pageController;
  bool _menuVisible = false;
  String _lastConfigKey = '';

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  PaginationConfig _buildConfig(ReaderSettings settings, Size size, Color textColor) {
    return PaginationConfig(
      fontSize: 18 * settings.fontScale,
      lineHeight: settings.lineHeight,
      pageWidth: size.width,
      pageHeight: size.height,
      horizontalMargin: settings.horizontalMargin,
      verticalMargin: settings.verticalMargin,
      fontFamily: settings.fontFamily,
      textColor: textColor,
    );
  }

  Future<void> _showNoteDialog(String selectedText) async {
    final TextEditingController inputController = TextEditingController();
    final String? content = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('写笔记'),
          content: TextField(
            controller: inputController,
            autofocus: true,
            maxLines: 5,
            decoration: const InputDecoration(hintText: '写下这一刻的想法...'),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, inputController.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    inputController.dispose();
    if (content == null || content.trim().isEmpty || !mounted) {
      return;
    }
    await context.read<ReaderController>().addNote(selectedText, content.trim());
  }

  void _openChapterSheet() {
    final ReaderController reader = context.read<ReaderController>();
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return ListView.builder(
          itemCount: reader.chapters.length,
          itemBuilder: (BuildContext context, int index) {
            final bool current = index == reader.chapterIndex;
            return ListTile(
              title: Text(
                reader.chapters[index].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: current ? Theme.of(context).colorScheme.primary : null),
              ),
              trailing: current ? const Icon(Icons.bookmark, size: 16) : null,
              onTap: () {
                Navigator.pop(sheetContext);
                reader.openChapter(index);
              },
            );
          },
        );
      },
    );
  }

  void _openSettingsSheet() {
    ReaderSettingsSheet.show(context);
  }

  Future<void> _toggleNightMode() async {
    final SettingsController settingsController = context.read<SettingsController>();
    final ReaderSettings settings = settingsController.settings;
    final bool currentlyDark = resolveThemeMode(settings) == ThemeMode.dark;
    await settingsController.setThemeMode(currentlyDark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController settingsController = context.watch<SettingsController>();
    final ReaderController reader = context.watch<ReaderController>();
    final ReaderSettings settings = settingsController.settings;
    final ReadingPalette palette = ReadingPalette.all[settings.paletteIndex];
    final Size size = MediaQuery.of(context).size;

    final PaginationConfig config = _buildConfig(settings, size, palette.text);
    if (config.cacheKey != _lastConfigKey) {
      _lastConfigKey = config.cacheKey;
      reader.provideConfig(config);
      // 屏幕尺寸或外观变化：等当前帧布局完成再重排版，避免 build 期间改状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        reader.repaginate(config).then((_) {
          if (!mounted || !_pageController.hasClients) {
            return;
          }
          final int target = reader.pageIndex;
          if ((_pageController.page ?? target).round() != target) {
            _pageController.jumpToPage(target);
          }
        });
      });
    }

    final ReaderPage? page = reader.currentPage;

    return Scaffold(
      backgroundColor: palette.background,
      body: GestureDetector(
        onTap: () => setState(() => _menuVisible = !_menuVisible),
        child: Stack(
          children: <Widget>[
            if (reader.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (page != null)
              PageView.builder(
                key: ValueKey<int>(reader.chapterIndex),
                controller: _pageController,
                initialPage: math.max(0, math.min(reader.pageIndex, reader.pages.length - 1)),
                scrollDirection: settings.pageAnimation == PageAnimation.scroll
                    ? Axis.vertical
                    : Axis.horizontal,
                itemCount: reader.pages.length,
                onPageChanged: (int index) => reader.goToPage(index),
                itemBuilder: (BuildContext context, int index) {
                  return _PageContentView(
                    page: reader.pages[index],
                    palette: palette,
                    settings: settings,
                    onLongPressLine: _showNoteDialog,
                  );
                },
              )
            else
              Center(child: Text('章节加载失败', style: TextStyle(color: palette.text))),
            if (_menuVisible) ...<Widget>[
              _ReaderTopBar(
                palette: palette,
                chapterTitle: reader.chapters.isNotEmpty
                    ? reader.chapters[reader.chapterIndex].title
                    : '',
                isBookmarked: reader.isBookmarked,
                onBack: () => Navigator.pop(context),
                onToggleBookmark: () => reader.toggleBookmark(),
                onOpenAnnotations: () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const AnnotationsPage(),
                  ));
                },
              ),
              _ReaderBottomBar(
                palette: palette,
                pageIndex: reader.pageIndex,
                pageCount: reader.pages.length,
                isDark: resolveThemeMode(settings) == ThemeMode.dark,
                onPageChanged: (int index) => reader.goToPage(index),
                onOpenChapters: _openChapterSheet,
                onOpenSettings: _openSettingsSheet,
                onToggleNightMode: _toggleNightMode,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单页正文：按行渲染，首行缩进、标题居中、引用带侧边线、代码等宽。
class _PageContentView extends StatelessWidget {
  const _PageContentView({
    required this.page,
    required this.palette,
    required this.settings,
    required this.onLongPressLine,
  });

  final ReaderPage page;
  final ReadingPalette palette;
  final ReaderSettings settings;
  final Future<void> Function(String selectedText) onLongPressLine;

  @override
  Widget build(BuildContext context) {
    final double baseSize = 18 * settings.fontScale;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: settings.horizontalMargin,
        vertical: settings.verticalMargin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: page.lines.map((PageLine line) => _buildLine(line, baseSize)).toList(),
      ),
    );
  }

  Widget _buildLine(PageLine line, double baseSize) {
    final TextStyle style = TextStyle(
      fontSize: baseSize,
      height: settings.lineHeight,
      color: palette.text,
      fontFamily: settings.fontFamily == 'system' ? null : settings.fontFamily,
    );
    if (line.isHeading) {
      final double scale = 1.3 - 0.1 * (line.headingLevel - 1);
      return Padding(
        padding: EdgeInsets.symmetric(vertical: baseSize * 0.3),
        child: Text(
          line.text,
          textAlign: TextAlign.center,
          style: style.copyWith(fontSize: baseSize * scale, fontWeight: FontWeight.bold),
        ),
      );
    }
    if (line.kind == ParagraphKind.quote) {
      return Container(
        margin: EdgeInsets.symmetric(vertical: baseSize * 0.2),
        padding: EdgeInsets.only(left: baseSize * 0.8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: palette.secondary, width: 2)),
        ),
        child: Text(line.text, style: style.copyWith(color: palette.secondary)),
      );
    }
    if (line.kind == ParagraphKind.code) {
      return Container(
        margin: EdgeInsets.symmetric(vertical: baseSize * 0.2),
        padding: EdgeInsets.all(baseSize * 0.5),
        color: palette.secondary.withOpacity(0.12),
        child: Text(line.text, style: style.copyWith(fontFamily: 'monospace')),
      );
    }
    if (line.isFirstLineOfParagraph) {
      return Padding(
        padding: EdgeInsets.only(left: baseSize * 2),
        child: _lineText(line, style),
      );
    }
    return _lineText(line, style);
  }

  Widget _lineText(PageLine line, TextStyle style) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => onLongPressLine(line.text),
      child: Text(line.text, style: style),
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.palette,
    required this.chapterTitle,
    required this.isBookmarked,
    required this.onBack,
    required this.onToggleBookmark,
    required this.onOpenAnnotations,
  });

  final ReadingPalette palette;
  final String chapterTitle;
  final bool isBookmarked;
  final VoidCallback onBack;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenAnnotations;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: palette.background.withOpacity(0.96),
        child: SafeArea(
          child: SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                IconButton(icon: const Icon(Icons.arrow_back), color: palette.text, onPressed: onBack),
                Expanded(
                  child: Text(
                    chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.text, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border),
                  color: palette.text,
                  tooltip: '书签',
                  onPressed: onToggleBookmark,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note),
                  color: palette.text,
                  tooltip: '书签与笔记',
                  onPressed: onOpenAnnotations,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.palette,
    required this.pageIndex,
    required this.pageCount,
    required this.isDark,
    required this.onPageChanged,
    required this.onOpenChapters,
    required this.onOpenSettings,
    required this.onToggleNightMode,
  });

  final ReadingPalette palette;
  final int pageIndex;
  final int pageCount;
  final bool isDark;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleNightMode;

  @override
  Widget build(BuildContext context) {
    final double sliderMax = math.max(1, pageCount - 1).toDouble();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: palette.background.withOpacity(0.96),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('${pageIndex + 1}/$pageCount', style: TextStyle(color: palette.secondary, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: math.min(pageIndex, sliderMax).toDouble(),
                        max: sliderMax,
                        onChanged: (double value) => onPageChanged(value.round()),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    _BarButton(icon: Icons.menu_book, label: '目录', palette: palette, onPressed: onOpenChapters),
                    _BarButton(
                      icon: isDark ? Icons.wb_sunny : Icons.nightlight_round,
                      label: isDark ? '日间' : '夜间',
                      palette: palette,
                      onPressed: onToggleNightMode,
                    ),
                    _BarButton(icon: Icons.format_size, label: '设置', palette: palette, onPressed: onOpenSettings),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final ReadingPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: palette.text, size: 18),
      label: Text(label, style: TextStyle(color: palette.text)),
    );
  }
}
