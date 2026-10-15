import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/data/dao/book_dao.dart';
import 'package:novel_reader/data/dao/chapter_dao.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/bookmark.dart';
import 'package:novel_reader/models/chapter.dart';
import 'package:novel_reader/models/note.dart';

import 'test_support.dart';

/// 导入→入库→删书 全链路功能测试（FT-IMPORT 系列）。
/// 输入为仓库内 test_books 真实样例文件，预期值来自探针实测（先实测后断言）。
void main() {
  group('FT-IMPORT 导入管线', () {
    late TestHarness harness;

    setUp(() async {
      harness = await createHarness();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('FT-IMPORT-01 导入 txt 样例书：章节/区间/进度全链路正确', () async {
      final Book book = await harness.bookRepository.importFile(
        sampleBookPath('测试书1-雨夜听刀.txt'),
      );

      // 实测：书名取首行「雨夜听刀」，章前杂论落入「正文」章，共 5 章
      expect(book.title, '雨夜听刀');
      expect(book.format, 'txt');
      expect(book.chapterCount, 5);
      expect(book.totalChars, greaterThan(0));

      // content.jsonl 每行必须是合法 JSON 块
      final List<String> lines =
          await File(book.contentPath).readAsLines(encoding: utf8);
      expect(lines, isNotEmpty);
      for (String line in lines) {
        final Map<String, Object?> json =
            jsonDecode(line) as Map<String, Object?>;
        expect(json['text'], isA<String>());
      }

      // 章节区间必须连续、无重叠、覆盖全文
      final List<Chapter> chapters =
          await ChapterDao(harness.database).findByBook(book.id);
      expect(chapters.length, book.chapterCount);
      expect(chapters.first.title, '正文');
      expect(chapters.first.paragraphStart, 0);
      expect(chapters.last.paragraphEnd, lines.length);
      for (int i = 1; i < chapters.length; i++) {
        expect(chapters[i].paragraphStart, chapters[i - 1].paragraphEnd,
            reason: '章节区间必须首尾相接');
      }

      // 导入即初始化进度（章 0 锚点、0%）
      final List<Map<String, Object?>> progressRows =
          await harness.database.query('progress', where: 'book_id = ?', whereArgs: <Object?>[book.id]);
      expect(progressRows.length, 1);
      expect(progressRows.first['chapter_index'], 0);
      expect(progressRows.first['percent'], 0.0);
    });

    test('FT-IMPORT-02 导入 md 样例书：标题切章 + 引用/列表/代码块结构保留', () async {
      final Book book = await harness.bookRepository.importFile(
        sampleBookPath('测试书2-山海食肆.md'),
      );

      expect(book.format, 'md');
      expect(book.chapterCount, 4, reason: '章前引用落入「正文」章 + 3 个二级标题章');

      final List<Chapter> chapters =
          await ChapterDao(harness.database).findByBook(book.id);
      expect(chapters.map((Chapter c) => c.title),
          containsAll(<String>['第一章 开张', '第二章 常客', '第三章 打烊']));

      // 结构块：引用 kind=quote、代码块 kind=code、标题 kind=heading 必须存在
      final List<String> lines =
          await File(book.contentPath).readAsLines(encoding: utf8);
      final Set<String> kinds = <String>{
        for (String line in lines)
          (jsonDecode(line) as Map<String, Object?>)['kind'] as String,
      };
      expect(kinds, containsAll(<String>['quote', 'code', 'heading']));

      // DEF-01 修复：md 首行「# 书名」的标题标记须剥离，书架显示纯书名
      expect(book.title, '测试书2-山海食肆');
    });

    test('FT-IMPORT-03 导入 docx 样例书：Word 标题样式识别为章节', () async {
      final Book book = await harness.bookRepository.importFile(
        sampleBookPath('测试书3-雾中列车.docx'),
      );

      expect(book.format, 'docx');
      expect(book.chapterCount, 4, reason: 'Heading1 书名 + 3 个 Heading2 章节');
      expect(book.title, '测试书3-雾中列车');

      final List<Chapter> chapters =
          await ChapterDao(harness.database).findByBook(book.id);
      expect(chapters[0].title, '测试书3-雾中列车');
      expect(chapters[1].title, '第一章 末班车');
      expect(chapters[2].title, '第二章 不存在的站点');
      expect(chapters[3].title, '第三章 到站');

      // 正文中文无乱码
      final List<String> lines =
          await File(book.contentPath).readAsLines(encoding: utf8);
      final String all = lines.join('\n');
      expect(all, contains('末班车提示音'));
      expect(all, contains('永安镇'));
    });

    test('FT-IMPORT-04 边界 txt（BOM+CRLF+全角空格+连续空行）健壮解析', () async {
      final Book book = await harness.bookRepository.importFile(
        sampleBookPath('测试书4-边界用例.txt'),
      );

      expect(book.chapterCount, 3, reason: '正文 + 第一章 + 第二章');
      expect(book.title, '边界测试-乱糟糟的txt');

      final List<String> lines =
          await File(book.contentPath).readAsLines(encoding: utf8);
      final String all = lines.join('\n');
      // BOM 与全角空格不得混进正文
      expect(all, isNot(contains('\uFEFF')));
      // 连续空行不得产生空段落块
      for (String line in lines) {
        final Map<String, Object?> json =
            jsonDecode(line) as Map<String, Object?>;
        expect((json['text'] as String).trim(), isNotEmpty);
      }
      // 硬换行续行合并生效（第一段被拼回整段）
      expect(all, contains('这一段行尾有很多空格'));
    });

    test('FT-IMPORT-05 同一文件重复导入得到两本独立书籍', () async {
      final Book first = await harness.bookRepository.importFile(
        sampleBookPath('测试书1-雨夜听刀.txt'),
      );
      final Book second = await harness.bookRepository.importFile(
        sampleBookPath('测试书1-雨夜听刀.txt'),
      );

      expect(first.id, isNot(second.id));
      expect(first.contentPath, isNot(second.contentPath));
      final List<Map<String, Object?>> rows =
          await harness.database.query('books');
      expect(rows.length, 2);
    });

    test('FT-IMPORT-06 非法 UTF-8 二进制抛中文 ImportException 且不留半成品', () async {
      final Directory temp =
          await Directory.systemTemp.createTemp('binary_book_');
      try {
        final File fake = File('${temp.path}/伪装.txt');
        // 0x80 起的续延字节无前导字节：UTF-8 解码失败；GBK 0x80 为非法前导亦失败
        await fake.writeAsBytes(const <int>[0x80, 0x81, 0x82, 0x83]);

        await expectLater(
          harness.bookRepository.importFile(fake.path),
          throwsA(isA<ImportException>()
              .having((ImportException e) => e.message, 'message',
                  contains('编码'))),
        );
        final List<Map<String, Object?>> rows =
            await harness.database.query('books');
        expect(rows, isEmpty, reason: '失败导入不得留下任何书籍记录');
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('FT-IMPORT-07 纯 ASCII 控制字符文件被二进制防护拒绝', () async {
      final Directory temp =
          await Directory.systemTemp.createTemp('ctrl_book_');
      try {
        final File fake = File('${temp.path}/控制字符.txt');
        // 0x00-0x08 均为合法 ASCII：UTF-8 解码成功，靠控制字符比例校验拦下
        await fake.writeAsBytes(const <int>[0, 1, 2, 3, 4, 5, 6, 7, 8]);

        // DEF-02 修复：解码后校验控制字符占比，超过阈值即拒绝
        await expectLater(
          harness.bookRepository.importFile(fake.path),
          throwsA(isA<ImportException>()
              .having((ImportException e) => e.message, 'message',
                  contains('二进制'))),
        );
        final List<Map<String, Object?>> rows =
            await harness.database.query('books');
        expect(rows, isEmpty, reason: '拒绝的导入不得留下任何书籍记录');
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('FT-IMPORT-08 删书级联清除书籍/章节/进度/书签/笔记/正文文件', () async {
      final Book book = await harness.bookRepository.importFile(
        sampleBookPath('测试书1-雨夜听刀.txt'),
      );
      await harness.annotationRepository.addBookmark(_bookmark(book.id));
      await harness.annotationRepository.addNote(_note(book.id));

      await harness.bookRepository.deleteBook(book.id);

      expect(await BookDao(harness.database).findById(book.id), isNull);
      expect(await ChapterDao(harness.database).findByBook(book.id), isEmpty);
      final List<Map<String, Object?>> progress = await harness.database
          .query('progress', where: 'book_id = ?', whereArgs: <Object?>[book.id]);
      expect(progress, isEmpty);
      final List<Map<String, Object?>> bookmarks = await harness.database
          .query('bookmarks', where: 'book_id = ?', whereArgs: <Object?>[book.id]);
      expect(bookmarks, isEmpty);
      final List<Map<String, Object?>> notes = await harness.database
          .query('notes', where: 'book_id = ?', whereArgs: <Object?>[book.id]);
      expect(notes, isEmpty);
      expect(await File(book.contentPath).exists(), isFalse,
          reason: '正文 content.jsonl 必须随删书移除');
    });
  });
}

Bookmark _bookmark(String bookId) => Bookmark(
      id: 'bm-test-1',
      bookId: bookId,
      chapterIndex: 1,
      paragraphIndex: 0,
      lineIndex: 0,
      chapterTitle: '第一章 雨夜来客',
      excerpt: '暴雨下了整整一夜',
      comment: '',
      createdAt: 1000,
      updatedAt: 1000,
    );

ReadingNote _note(String bookId) => ReadingNote(
      id: 'note-test-1',
      bookId: bookId,
      chapterIndex: 1,
      paragraphIndex: 0,
      lineIndex: 0,
      chapterTitle: '第一章 雨夜来客',
      selectedText: '暴雨下了整整一夜',
      content: '开篇氛围好',
      createdAt: 1000,
      updatedAt: 1000,
    );
