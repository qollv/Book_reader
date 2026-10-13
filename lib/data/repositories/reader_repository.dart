import 'dart:convert';
import 'dart:io';

import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/core/pagination/page_line.dart';
import 'package:novel_reader/core/pagination/paginator.dart';
import 'package:novel_reader/data/dao/chapter_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/models/chapter.dart';
import 'package:novel_reader/models/reading_progress.dart';

/// 阅读数据访问：章节、正文块、分页结果缓存、进度。
class ReaderRepository {
  ReaderRepository({required ChapterDao chapterDao, required ProgressDao progressDao})
      : _chapterDao = chapterDao,
        _progressDao = progressDao;

  final ChapterDao _chapterDao;
  final ProgressDao _progressDao;

  // 分页结果缓存：key = bookId|chapterIndex|排版参数指纹
  final Map<String, List<ReaderPage>> _pageCache = <String, List<ReaderPage>>{};

  Future<List<Chapter>> loadChapters(String bookId) {
    return _chapterDao.findByBook(bookId);
  }

  /// 加载某章段落块：content.jsonl 一段一行，按章节记录的区间读取。
  Future<List<ParagraphBlock>> loadChapterBlocks(String contentPath, Chapter chapter) async {
    final File file = File(contentPath);
    if (!await file.exists()) {
      return <ParagraphBlock>[];
    }
    final List<String> lines = await file.readAsLines(encoding: utf8);
    final int end = chapter.paragraphEnd.clamp(0, lines.length);
    if (chapter.paragraphStart >= end) {
      return <ParagraphBlock>[];
    }
    final List<ParagraphBlock> blocks = <ParagraphBlock>[];
    for (int i = chapter.paragraphStart; i < end; i++) {
      if (lines[i].trim().isEmpty) {
        continue;
      }
      final Map<String, Object?> json = jsonDecode(lines[i]) as Map<String, Object?>;
      blocks.add(ParagraphBlock.fromJson(json));
    }
    return blocks;
  }

  /// 取某章分页结果，命中缓存直接返回；排版参数变化后 key 不同，自动重算。
  Future<List<ReaderPage>> getPages({
    required String bookId,
    required int chapterIndex,
    required List<ParagraphBlock> blocks,
    required PaginationConfig config,
  }) async {
    final String key = '$bookId|$chapterIndex|${config.cacheKey}';
    final List<ReaderPage>? cached = _pageCache[key];
    if (cached != null) {
      return cached;
    }
    final List<ReaderPage> pages = Paginator().paginate(blocks, config);
    _pageCache[key] = pages;
    return pages;
  }

  void clearCache() {
    _pageCache.clear();
  }

  Future<ReadingProgress?> loadProgress(String bookId) {
    return _progressDao.findByBook(bookId);
  }

  Future<void> saveProgress(ReadingProgress progress) {
    return _progressDao.upsert(progress);
  }
}
