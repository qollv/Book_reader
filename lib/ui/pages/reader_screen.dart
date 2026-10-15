import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/line_box.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/state/settings_controller.dart';
import 'package:novel_reader/ui/pages/annotations_page.dart';
import 'package:novel_reader/ui/theme/reading_palettes.dart';
import 'package:novel_reader/ui/theme/theme_mode_resolver.dart';
import 'package:novel_reader/ui/widgets/reader_settings_sheet.dart';

/// 阅读器页面：分页渲染 + 点按呼出菜单 + 章节/进度/书签/笔记入口。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  PageController? _pageController;
  int _controllerChapter = -1;
  bool _menuVisible = false;
  String _lastConfigKey = '';

  /// 章节切换时新建控制器落到目标页；同章复用，保持滚动位置。
  PageController _controllerFor(int chapterIndex, int pageIndex) {
    if (_pageController == null || _controllerChapter != chapterIndex) {
      _pageController?.dispose();
      _pageController = PageController(initialPage: pageIndex);
      _controllerChapter = chapterIndex;
    }
    return _pageController!;
  }

  @override
  void dispose() {
    _pageController?.dispose();
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
          final PageController? controller = _pageController;
          if (!mounted || controller == null || !controller.hasClients) {
            return;
          }
          final int target = reader.pageIndex;
          if ((controller.page ?? target).round() != target) {
            controller.jumpToPage(target);
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
                controller: _controllerFor(
                  reader.chapterIndex,
                  math.max(0, math.min(reader.pageIndex, reader.pages.length - 1)),
                ),
                scrollDirection: settings.pageAnimation == PageAnimation.scroll
                    ? Axis.vertical
                    : Axis.horizontal,
                itemCount: reader.pages.length,
                onPageChanged: (int index) => reader.goToPage(index),
                itemBuilder: (BuildContext context, int index) {
                  return ReaderPageContentView(
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
///
/// 公开而非私有，是为了让测试能把它真的渲染出来、量出实际高度，
/// 从而断言「分页说放得下的页，渲染出来确实放得下」——
/// 这个不变量原先被破坏了（代码块小屏溢出 120px），
/// 而只靠单元测试看不见，必须量真东西。
class ReaderPageContentView extends StatelessWidget {
  const ReaderPageContentView({
    super.key,
    required this.page,
    required this.palette,
    required this.settings,
    required this.onLongPressLine,
  });

  /// 内容容器的 key：测试据此读取内容实际高度。
  static const Key contentKey = ValueKey<String>('reader-page-content');

  final ReaderPage page;
  final ReadingPalette palette;
  final ReaderSettings settings;
  final Future<void> Function(String selectedText) onLongPressLine;

  @override
  Widget build(BuildContext context) {
    final double baseSize = 18 * settings.fontScale;
    final List<PageLine> lines = page.lines;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: settings.horizontalMargin,
        vertical: settings.verticalMargin,
      ),
      child: Column(
        key: contentKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < lines.length; i++)
            _buildLine(lines[i], baseSize, isPageFirst: i == 0),
        ],
      ),
    );
  }

  Widget _buildLine(PageLine line, double baseSize, {required bool isPageFirst}) {
    // 字体缩放与字体族都来自共享约定（core/pagination/line_box.dart），
    // 分页器用的是同一份数字，否则量的和渲染的不是同一件事
    final TextStyle style = TextStyle(
      fontSize: baseSize * LineBox.fontScaleFactor(line.kind, line.headingLevel),
      height: settings.lineHeight,
      color: palette.text,
      fontFamily: LineBox.fontFamily(line.kind, settings.fontFamily),
    );

    final Widget content = _buildLineContent(line, baseSize, style);

    // 段间距：分页器按「段首行、且不是本页首行」计入高度，渲染必须一致。
    // 原先分页器算了、渲染器没画，等于白留了半行空间，也说明两边本就在漂移。
    final double gap = !isPageFirst && line.isFirstLineOfParagraph
        ? LineBox.paragraphSpacingPx(baseSize)
        : 0;
    if (gap <= 0) {
      return content;
    }
    return Padding(padding: EdgeInsets.only(top: gap), child: content);
  }

  Widget _buildLineContent(PageLine line, double baseSize, TextStyle style) {
    switch (line.kind) {
      case ParagraphKind.heading:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: baseSize * LineBox.headingPaddingVertical),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: style.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      case ParagraphKind.quote:
        return Container(
          margin: EdgeInsets.symmetric(vertical: baseSize * LineBox.quoteMarginVertical),
          padding: EdgeInsets.only(left: baseSize * 0.8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: palette.secondary, width: 2)),
          ),
          child: Text(line.text, style: style.copyWith(color: palette.secondary)),
        );
      case ParagraphKind.code:
        return Container(
          margin: EdgeInsets.symmetric(vertical: baseSize * LineBox.codeMarginVertical),
          padding: EdgeInsets.all(baseSize * LineBox.codePadding),
          color: palette.secondary.withValues(alpha: 0.12),
          child: Text(line.text, style: style),
        );
      case ParagraphKind.paragraph:
        if (line.isFirstLineOfParagraph) {
          return Padding(
            padding: EdgeInsets.only(left: baseSize * 2),
            child: _lineText(line, style),
          );
        }
        return _lineText(line, style);
    }
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
        color: palette.background.withValues(alpha: 0.96),
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
        color: palette.background.withValues(alpha: 0.96),
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
                        value: pageIndex.toDouble().clamp(0.0, sliderMax),
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
