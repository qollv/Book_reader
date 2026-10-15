import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/data/dao/chapter_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/data/repositories/reader_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/chapter.dart';
import 'package:novel_reader/models/reading_progress.dart';

import '../support/test_database.dart';

/// 模型解析健壮性回归测试。
///
/// 背景：这些 `fromJson` / `fromRow` 原来一律用 `as int` / `as String`
/// 硬转，缺字段或类型不符就抛。而 content.jsonl 是**逐行**读的：
/// 一行缺 `level` 会让整章打不开（历史文件、手改文件、写到一半被杀都会踩到）。
/// 阅读类应用里，「一行脏数据毁掉一整本书」是不可接受的失败模式。
void main() {
  group('ParagraphBlock.fromJson', () {
    test('空对象退化成普通空段落而不抛异常', () {
      final ParagraphBlock block = ParagraphBlock.fromJson(<String, Object?>{});
      expect(block.text, '');
      expect(block.kind, ParagraphKind.paragraph);
      expect(block.headingLevel, 1);
    });

    test('缺 level 时用 1（原来会 type Null is not a subtype of int）', () {
      final ParagraphBlock block =
          ParagraphBlock.fromJson(<String, Object?>{'text': 'abc', 'kind': 'paragraph'});
      expect(block.text, 'abc');
      expect(block.headingLevel, 1);
    });

    test('level 是 double（JSON 数字）时取整', () {
      final ParagraphBlock block =
          ParagraphBlock.fromJson(<String, Object?>{'text': 'x', 'level': 2.0});
      expect(block.headingLevel, 2);
    });

    test('level 越界被钳到 1..6', () {
      expect(ParagraphBlock.fromJson(<String, Object?>{'text': 'x', 'level': 99}).headingLevel, 6);
      expect(ParagraphBlock.fromJson(<String, Object?>{'text': 'x', 'level': 0}).headingLevel, 1);
      expect(ParagraphBlock.fromJson(<String, Object?>{'text': 'x', 'level': -3}).headingLevel, 1);
    });

    test('未知 kind 退化成普通段落', () {
      final ParagraphBlock block =
          ParagraphBlock.fromJson(<String, Object?>{'text': 'x', 'kind': 'rainbow'});
      expect(block.kind, ParagraphKind.paragraph);
    });

    test('text 不是字符串时退化成空串', () {
      expect(ParagraphBlock.fromJson(<String, Object?>{'text': 42}).text, '');
    });

    test('toJson → fromJson 往返一致', () {
      const ParagraphBlock original =
          ParagraphBlock(text: '第一行\n第二行', kind: ParagraphKind.heading, headingLevel: 2);
      final ParagraphBlock restored =
          ParagraphBlock.fromJson(jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>);
      expect(restored.text, original.text);
      expect(restored.kind, original.kind);
      expect(restored.headingLevel, original.headingLevel);
    });
  });

  group('行映射容错', () {
    test('Book.fromRow 残缺行不抛异常', () {
      final Book book = Book.fromRow(<String, Object?>{'id': 'b', 'title': 't'});
      expect(book.id, 'b');
      expect(book.title, 't');
      expect(book.author, '');
      expect(book.chapterCount, 0);
      expect(book.sourceId, '');
      expect(book.isOnline, isFalse);
    });

    test('Chapter.fromRow 残缺行不抛异常', () {
      final Chapter chapter = Chapter.fromRow(<String, Object?>{});
      expect(chapter.title, '');
      expect(chapter.index, 0);
      expect(chapter.paragraphStart, 0);
    });

    test('ReadingProgress.fromRow 的 percent 是整数时不抛异常', () {
      final ReadingProgress progress = ReadingProgress.fromRow(<String, Object?>{
        'book_id': 'b',
        'chapter_index': 0,
        'paragraph_index': 0,
        'line_index': 0,
        'percent': 0,
        'updated_at': 0,
      });
      expect(progress.percent, 0.0);
    });

    test('ReadingProgress.percent 被钳到 0..1', () {
      final ReadingProgress over = ReadingProgress.fromRow(<String, Object?>{'percent': 3.7});
      expect(over.percent, 1.0);
      final ReadingProgress under = ReadingProgress.fromRow(<String, Object?>{'percent': -2});
      expect(under.percent, 0.0);
    });
  });

  group('content.jsonl 逐行容错', () {
    late Database db;
    late ReaderRepository repository;
    late Directory dir;

    setUp(() async {
      db = await openTestDatabase();
      repository = ReaderRepository(
        chapterDao: ChapterDao(db),
        progressDao: ProgressDao(db),
      );
      dir = await Directory.systemTemp.createTemp('jsonl_regression_');
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    Future<String> writeJsonl(List<String> lines) async {
      final String path = '${dir.path}${Platform.pathSeparator}content.jsonl';
      await File(path).writeAsString(lines.join('\n'), encoding: utf8);
      return path;
    }

    const Chapter chapter = Chapter(
      bookId: 'b',
      index: 0,
      title: '第一章',
      paragraphStart: 0,
      paragraphEnd: 5,
    );

    test('一行损坏只跳过那一行，其余照常读出', () async {
      final String path = await writeJsonl(<String>[
        jsonEncode(const ParagraphBlock(text: '第一段', kind: ParagraphKind.paragraph).toJson()),
        '{ 这不是合法 JSON',
        jsonEncode(const ParagraphBlock(text: '第二段', kind: ParagraphKind.paragraph).toJson()),
        '[1,2,3]',
        jsonEncode(const ParagraphBlock(text: '第三段', kind: ParagraphKind.paragraph).toJson()),
      ]);

      final List<ParagraphBlock> blocks = await repository.loadChapterBlocks(path, chapter);

      expect(blocks.map((ParagraphBlock b) => b.text).toList(),
          <String>['第一段', '第二段', '第三段']);
      expect(repository.lastSkippedLines, 2, reason: '两行坏数据要被记下来');
    });

    test('缺 level 的行照常读出（原来会让整章失败）', () async {
      final String path = await writeJsonl(<String>['{"text":"没有级别的段","kind":"paragraph"}']);

      final List<ParagraphBlock> blocks = await repository.loadChapterBlocks(path, chapter);

      expect(blocks.single.text, '没有级别的段');
      expect(blocks.single.headingLevel, 1);
    });

    test('整行空白被跳过且不计入损坏', () async {
      final String path = await writeJsonl(<String>[
        jsonEncode(const ParagraphBlock(text: '第一段', kind: ParagraphKind.paragraph).toJson()),
        '   ',
        '',
      ]);

      final List<ParagraphBlock> blocks = await repository.loadChapterBlocks(path, chapter);
      expect(blocks, hasLength(1));
      expect(repository.lastSkippedLines, 0);
    });

    test('文件不存在时返回空列表而不是抛异常', () async {
      final List<ParagraphBlock> blocks = await repository.loadChapterBlocks(
        '${dir.path}${Platform.pathSeparator}nope.jsonl',
        chapter,
      );
      expect(blocks, isEmpty);
    });
  });
}
