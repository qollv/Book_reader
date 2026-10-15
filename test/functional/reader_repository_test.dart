import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/models/chapter.dart';

import 'test_support.dart';

/// 正文区间读取 + 分页缓存功能测试（FT-REPO 系列）。
void main() {
  group('FT-REPO 数据读取与缓存', () {
    late TestHarness harness;
    late Directory tempDir;

    setUp(() async {
      harness = await createHarness();
      tempDir = await Directory.systemTemp.createTemp('repo_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
      await harness.dispose();
    });

    Future<File> writeJsonl(List<ParagraphBlock> blocks) async {
      final File file = File('${tempDir.path}/content.jsonl');
      await file.writeAsString(
        blocks.map((ParagraphBlock b) => jsonEncode(b.toJson())).join('\n'),
        encoding: utf8,
      );
      return file;
    }

    List<ParagraphBlock> sampleBlocks() => const <ParagraphBlock>[
          ParagraphBlock(text: '第一段', kind: ParagraphKind.paragraph),
          ParagraphBlock(text: '第二段', kind: ParagraphKind.paragraph),
          ParagraphBlock(text: '第一章 标题', kind: ParagraphKind.heading),
          ParagraphBlock(text: '第三段', kind: ParagraphKind.paragraph),
        ];

    test('FT-REPO-01 按章节区间精确读取段落块', () async {
      final File file = await writeJsonl(sampleBlocks());
      final List<ParagraphBlock> blocks =
          await harness.readerRepository.loadChapterBlocks(
        file.path,
        const Chapter(
          bookId: 'b',
          index: 0,
          title: '第一章',
          paragraphStart: 1,
          paragraphEnd: 3,
        ),
      );
      expect(blocks.length, 2);
      expect(blocks[0].text, '第二段');
      expect(blocks[1].text, '第一章 标题');
      expect(blocks[1].kind, ParagraphKind.heading);
    });

    test('FT-REPO-02 空行被跳过、区间越界被 clamp', () async {
      final File file = File('${tempDir.path}/content.jsonl');
      await file.writeAsString('{"text":"甲","kind":"paragraph","level":1}\n\n'
          '{"text":"乙","kind":"paragraph","level":1}\n');

      final List<ParagraphBlock> blocks =
          await harness.readerRepository.loadChapterBlocks(
        file.path,
        const Chapter(
          bookId: 'b',
          index: 0,
          title: '第一章',
          paragraphStart: 0,
          paragraphEnd: 999, // 超出总行数 → clamp
        ),
      );
      expect(blocks.length, 2, reason: '空行跳过 + end 越界 clamp 到 2');
    });

    test('FT-REPO-03 start >= end 或文件不存在时返回空', () async {
      final File file = await writeJsonl(sampleBlocks());
      expect(
        await harness.readerRepository.loadChapterBlocks(
          file.path,
          const Chapter(bookId: 'b', index: 0, title: 't', paragraphStart: 3, paragraphEnd: 3),
        ),
        isEmpty,
      );
      expect(
        await harness.readerRepository.loadChapterBlocks(
          '${tempDir.path}/not-exist.jsonl',
          const Chapter(bookId: 'b', index: 0, title: 't', paragraphStart: 0, paragraphEnd: 3),
        ),
        isEmpty,
        reason: '正文文件缺失不抛异常，返回空由上层呈现错误页',
      );
    });

    test('FT-REPO-04 损坏的 jsonl 行抛出异常（由打开流程兜底为错误页）', () async {
      final File file = File('${tempDir.path}/content.jsonl');
      await file.writeAsString('{"text":"甲","kind":"paragraph","level":1}\n这不是JSON\n');
      await expectLater(
        harness.readerRepository.loadChapterBlocks(
          file.path,
          const Chapter(bookId: 'b', index: 0, title: 't', paragraphStart: 0, paragraphEnd: 2),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('FT-REPO-05 分页缓存命中返回同一实例，LRU 上限 12 章', () async {
      const PaginationConfig config = PaginationConfig(
        fontSize: 18,
        lineHeight: 1.8,
        pageWidth: 360,
        pageHeight: 320,
        horizontalMargin: 24,
        verticalMargin: 20,
      );
      final List<ParagraphBlock> blocks = sampleBlocks();

      final List<ReaderPage> first = await harness.readerRepository.getPages(
        bookId: 'b1', chapterIndex: 0, blocks: blocks, config: config,
      );
      final List<ReaderPage> hit = await harness.readerRepository.getPages(
        bookId: 'b1', chapterIndex: 0, blocks: blocks, config: config,
      );
      expect(identical(first, hit), isTrue, reason: '同 key 必须命中缓存');

      // 排版参数变化 → key 不同 → 重新计算
      final List<ReaderPage> afterConfigChange =
          await harness.readerRepository.getPages(
        bookId: 'b1', chapterIndex: 0, blocks: blocks,
        config: config.copyWith(fontSize: 20),
      );
      expect(identical(first, afterConfigChange), isFalse);

      // 连续灌 13 章 → 第 1 章被淘汰（LRU 容量 12）
      for (int i = 0; i < 13; i++) {
        await harness.readerRepository.getPages(
          bookId: 'b1', chapterIndex: i, blocks: blocks, config: config,
        );
      }
      final List<ReaderPage> evicted = await harness.readerRepository.getPages(
        bookId: 'b1', chapterIndex: 0, blocks: blocks, config: config,
      );
      expect(identical(first, evicted), isFalse,
          reason: '超出 LRU 容量的最旧章节应被淘汰');
      // 最近一章仍命中
      final List<ReaderPage> recent = await harness.readerRepository.getPages(
        bookId: 'b1', chapterIndex: 12, blocks: blocks, config: config,
      );
      expect(recent, isNotEmpty);
    });
  });
}

extension _CopyWith on PaginationConfig {
  PaginationConfig copyWith({double? fontSize}) => PaginationConfig(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        horizontalMargin: horizontalMargin,
        verticalMargin: verticalMargin,
        fontFamily: fontFamily,
        textColor: textColor,
      );
}
