import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/models/bookmark.dart';
import 'package:novel_reader/state/reader_controller.dart';
import 'package:novel_reader/ui/theme/reading_palettes.dart';

/// 书签与笔记页：两个 Tab，点击条目跳回原文位置。
class AnnotationsPage extends StatelessWidget {
  const AnnotationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ReaderController reader = context.watch<ReaderController>();
    final ReadingPalette palette = ReadingPalette.all[0];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('书签与笔记'),
          bottom: const TabBar(tabs: <Widget>[
            Tab(text: '书签'),
            Tab(text: '笔记'),
          ]),
        ),
        body: TabBarView(
          children: <Widget>[
            _BookmarkList(reader: reader, palette: palette),
            _NoteList(reader: reader, palette: palette),
          ],
        ),
      ),
    );
  }
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({required this.reader, required this.palette});

  final ReaderController reader;
  final ReadingPalette palette;

  @override
  Widget build(BuildContext context) {
    if (reader.bookmarks.isEmpty) {
      return const Center(child: Text('还没有书签，阅读时点右上角书签图标添加'));
    }
    return ListView.separated(
      itemCount: reader.bookmarks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final bookmark = reader.bookmarks[index];
        return ListTile(
          title: Text(bookmark.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${bookmark.chapterTitle} · ${_formatTime(bookmark.createdAt)}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => reader.deleteBookmark(bookmark.id),
          ),
          onTap: () => _jump(context, bookmark),
        );
      },
    );
  }

  void _jump(BuildContext context, Bookmark bookmark) {
    reader.jumpTo(
      chapterIndex: bookmark.chapterIndex,
      paragraphIndex: bookmark.paragraphIndex,
      lineIndex: bookmark.lineIndex,
    );
    Navigator.pop(context);
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({required this.reader, required this.palette});

  final ReaderController reader;
  final ReadingPalette palette;

  @override
  Widget build(BuildContext context) {
    if (reader.notes.isEmpty) {
      return const Center(child: Text('还没有笔记，阅读时长按正文行即可记笔记'));
    }
    return ListView.separated(
      itemCount: reader.notes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final note = reader.notes[index];
        return ListTile(
          title: Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${note.chapterTitle} · 原文：${note.selectedText}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => reader.deleteNote(note.id),
          ),
          onTap: () => _editNote(context, note.id, note.content),
        );
      },
    );
  }

  Future<void> _editNote(BuildContext context, String noteId, String oldContent) async {
    final TextEditingController inputController = TextEditingController(text: oldContent);
    final String? content = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('编辑笔记'),
          content: TextField(controller: inputController, autofocus: true, maxLines: 5),
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
    if (content != null && content.trim().isNotEmpty && context.mounted) {
      await reader.updateNote(noteId, content.trim());
    }
  }
}

String _formatTime(int millis) {
  final DateTime time = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
