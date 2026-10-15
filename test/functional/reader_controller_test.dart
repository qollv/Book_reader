import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/reading_progress.dart';

import 'test_support.dart';

/// 阅读器状态机功能测试（FT-RC 系列）。
/// 覆盖开书/翻页/进度锚点/防抖/书签/笔记/重排版。
void main() {
  group('FT-RC 阅读器状态', () {
    late TestHarness harness;

    setUp(() async {
      harness = await createHarness();
      // 小页面高度 → 一章多页，翻页/锚点逻辑才有意义
      harness.readerController.provideConfig(const PaginationConfig(
        fontSize: 18,
        lineHeight: 1.8,
        pageWidth: 360,
        pageHeight: 320,
        horizontalMargin: 24,
        verticalMargin: 20,
      ));
    });

    tearDown(() async {
      await harness.dispose();
    });

    Future<Book> importSample() async {
      final Book book = await harness.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      await harness.readerController.openBook(book.id);
      return book;
    }

    test('FT-RC-01 打开不存在的书：明确错误文案且无残留内容', () async {
      await harness.readerController.openBook('no-such-book');
      expect(harness.readerController.error, '书籍不存在或已被删除');
      expect(harness.readerController.book, isNull);
      expect(harness.readerController.isLoading, isFalse);
    });

    test('FT-RC-02 打开失败后状态被清空（不残留上一本书）', () async {
      final Book book = await importSample();
      expect(harness.readerController.book, isNotNull);

      // 破坏正文文件后重新打开同一本书 → 错误页
      await File(book.contentPath).writeAsString('这不是合法JSON\n');
      await harness.readerController.openBook(book.id);
      expect(harness.readerController.error, isNotNull);
      expect(harness.readerController.error, contains('打开失败'));
      expect(harness.readerController.isLoading, isFalse);
      // DEF-07 修复：失败时连已赋值的新书引用一起清掉，不残留半开状态
      expect(harness.readerController.book, isNull);
      expect(harness.readerController.chapters, isEmpty);
      expect(harness.readerController.chapterIndex, 0);
      expect(harness.readerController.pageIndex, 0);
    });

    test('FT-RC-03 进度锚点恢复：进度记录在第 2 章则打开第 2 章', () async {
      final Book book = await importSample();
      await harness.readerRepository.saveProgress(ReadingProgress(
        bookId: book.id,
        chapterIndex: 1,
        paragraphIndex: 0,
        lineIndex: 0,
        percent: 0.2,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      await harness.readerController.openBook(book.id);
      expect(harness.readerController.chapterIndex, 1);
      expect(harness.readerController.pageIndex, 0);
    });

    test('FT-RC-04 goToPage 越界被忽略', () async {
      await importSample();
      // 第一章「正文」仅 3 行不足一页，切到第二章（约 12 行）拿多页场景
      await harness.readerController.openChapter(2);
      final int pages = harness.readerController.pages.length;
      expect(pages, greaterThan(1), reason: '小页面高度下一章应有多页');

      await harness.readerController.goToPage(-1);
      expect(harness.readerController.pageIndex, 0);
      await harness.readerController.goToPage(pages + 10);
      expect(harness.readerController.pageIndex, 0);
      await harness.readerController.goToPage(pages - 1);
      expect(harness.readerController.pageIndex, pages - 1);
    });

    test('FT-RC-05 书签切换幂等：加→在→删→不再', () async {
      await importSample();
      expect(harness.readerController.isBookmarked, isFalse);

      await harness.readerController.toggleBookmark();
      expect(harness.readerController.isBookmarked, isTrue);
      expect(harness.readerController.bookmarks.length, 1);
      final String firstId = harness.readerController.bookmarks.first.id;

      await harness.readerController.toggleBookmark();
      expect(harness.readerController.isBookmarked, isFalse);
      expect(harness.readerController.bookmarks, isEmpty);

      // 重新添加得到新 id（UUID 不重复）
      await harness.readerController.toggleBookmark();
      expect(harness.readerController.bookmarks.first.id, isNot(firstId));
    });

    test('FT-RC-06 笔记增改删往返', () async {
      await importSample();
      await harness.readerController.addNote('选中文本', '第一条笔记');
      expect(harness.readerController.notes.length, 1);
      final String noteId = harness.readerController.notes.first.id;

      await harness.readerController.updateNote(noteId, '修改后的笔记');
      expect(harness.readerController.notes.first.content, '修改后的笔记');

      await harness.readerController.deleteNote(noteId);
      expect(harness.readerController.notes, isEmpty);
    });

    test('FT-RC-07 进度写库防抖：300ms 内不落库、超时后落库', () async {
      await importSample();
      await harness.readerController.openChapter(2);
      await harness.readerController.goToPage(1);
      final String bookId = harness.readerController.book!.id;

      // 防抖窗口内：进度仍停留在第 0 页锚点
      await Future<void>.delayed(const Duration(milliseconds: 50));
      var row = await _progressRow(harness, bookId);
      expect(row['paragraph_index'], 0, reason: '防抖窗口内不得写库');

      // 超过 300ms：最后一次翻页落库
      await Future<void>.delayed(const Duration(milliseconds: 400));
      row = await _progressRow(harness, bookId);
      expect(row['paragraph_index'], greaterThan(0),
          reason: '翻到第 2 页后锚点段落下标应前进');
    });

    test('FT-RC-08 退出阅读器（dispose）前最后一次进度落库', () async {
      final TestHarness h = await createHarness();
      h.readerController.provideConfig(const PaginationConfig(
        fontSize: 18,
        lineHeight: 1.8,
        pageWidth: 360,
        pageHeight: 320,
        horizontalMargin: 24,
        verticalMargin: 20,
      ));
      final Book book = await h.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      await h.readerController.openBook(book.id);
      await h.readerController.openChapter(2);
      await h.readerController.goToPage(1);
      final String bookId = book.id;

      // 立即销毁：防抖定时器被取消，但 dispose 内同步补写
      h.readerController.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final List<Map<String, Object?>> rows = await h.database
          .query('progress', where: 'book_id = ?', whereArgs: <Object?>[bookId]);
      expect(rows.first['paragraph_index'], greaterThan(0),
          reason: 'dispose 必须补写最后进度，否则退出即丢位置');

      await h.dispose(disposeControllers: false);
    });

    test('FT-RC-09 bookPercent 单章时 = 章内页进度', () async {
      await importSample();
      final double expected =
          harness.readerController.pageIndex / harness.readerController.pages.length;
      expect(harness.readerController.bookPercent, closeTo(expected, 1e-9));
      expect(harness.readerController.bookPercent, greaterThanOrEqualTo(0));
      expect(harness.readerController.bookPercent, lessThanOrEqualTo(1));
    });

    test('FT-RC-10 重排版后锚点保持：改排版参数页索引仍指向原锚点附近', () async {
      await importSample();
      await harness.readerController.openChapter(2);
      await harness.readerController.goToPage(1);
      final int oldParagraph =
          harness.readerController.currentPage!.lines.first.paragraphIndex;

      await harness.readerController.repaginate(const PaginationConfig(
        fontSize: 22,
        lineHeight: 2.0,
        pageWidth: 360,
        pageHeight: 320,
        horizontalMargin: 24,
        verticalMargin: 20,
      ));

      final int newParagraph =
          harness.readerController.currentPage!.lines.first.paragraphIndex;
      expect(newParagraph, greaterThanOrEqualTo(oldParagraph),
          reason: '重排版后不得回退到更早的锚点');
    });

    test('FT-RC-11 目录跳章与书签跳转：跨章打开并定位', () async {
      await importSample();
      await harness.readerController.openChapter(2);
      expect(harness.readerController.chapterIndex, 2);

      // 跳到第 4 章某锚点
      await harness.readerController.jumpTo(
        chapterIndex: 3,
        paragraphIndex: 0,
        lineIndex: 0,
      );
      expect(harness.readerController.chapterIndex, 3);
      expect(harness.readerController.pageIndex, 0);

      // 章内跳转
      await harness.readerController.jumpTo(
        chapterIndex: 3,
        paragraphIndex: 1,
        lineIndex: 0,
      );
      expect(harness.readerController.chapterIndex, 3);
    });

    test('FT-RC-12 上一章/下一章边界：首章再上一章、末章再下一章无变化', () async {
      await importSample();
      await harness.readerController.previousChapter();
      expect(harness.readerController.chapterIndex, 0);

      final int last = harness.readerController.chapters.length - 1;
      await harness.readerController.openChapter(last);
      await harness.readerController.nextChapter();
      expect(harness.readerController.chapterIndex, last);
    });

    test('FT-RC-13 findPageForAnchor 锚点缺失时取最近邻而非静默回第 0 页', () async {
      await importSample();
      final List<ReaderPage> pages = harness.readerController.pages;
      // 目标段落下标超出全文 → 最后一页
      expect(findPageForAnchor(pages, 9999, 0), pages.length - 1);
      // 精确锚点 → 所在页
      final ReaderPage somePage = pages[pages.length - 1];
      expect(
        findPageForAnchor(
            pages, somePage.lines.first.paragraphIndex, somePage.lines.first.lineIndex),
        somePage.index,
      );
    });
  });
}

Future<Map<String, Object?>> _progressRow(TestHarness harness, String bookId) async {
  final List<Map<String, Object?>> rows = await harness.database
      .query('progress', where: 'book_id = ?', whereArgs: <Object?>[bookId]);
  return rows.single;
}
