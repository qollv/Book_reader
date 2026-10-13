import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:novel_reader/core/parsers/book_parser.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/data/dao/book_dao.dart';
import 'package:novel_reader/data/dao/chapter_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/data/repositories/annotation_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/chapter.dart';
import 'package:novel_reader/models/reading_progress.dart';

/// 导入管线：解析 → 落盘 content.jsonl → 写库。
class BookRepository {
  BookRepository({
    required BookDao bookDao,
    required ChapterDao chapterDao,
    required ProgressDao progressDao,
    required AnnotationRepository annotationRepository,
  }) : _bookDao = bookDao,
       _chapterDao = chapterDao,
       _progressDao = progressDao,
       _annotationRepository = annotationRepository;

  final BookDao _bookDao;
  final ChapterDao _chapterDao;
  final ProgressDao _progressDao;
  final AnnotationRepository _annotationRepository;

  /// 从本地文件导入一本书。解析失败时向外抛异常，不留下半成品。
  Future<Book> importFile(String sourcePath) async {
    final BookParser parser = parserForFile(sourcePath);
    final ParsedBook parsed = await parser.parseFile(sourcePath);

    final String bookId = const Uuid().v4();
    final Directory bookDir = await _ensureBookDir(bookId);
    final File contentFile = File(p.join(bookDir.path, 'content.jsonl'));

    final List<Chapter> chapters = <Chapter>[];
    final List<String> jsonlLines = <String>[];
    int paragraphCursor = 0;

    for (int i = 0; i < parsed.chapters.length; i++) {
      final ParsedChapter parsedChapter = parsed.chapters[i];
      for (ParagraphBlock block in parsedChapter.blocks) {
        jsonlLines.add(jsonEncode(block.toJson()));
      }
      chapters.add(Chapter(
        bookId: bookId,
        index: i,
        title: parsedChapter.title,
        paragraphStart: paragraphCursor,
        paragraphEnd: paragraphCursor + parsedChapter.blocks.length,
      ));
      paragraphCursor += parsedChapter.blocks.length;
    }
    await contentFile.writeAsString(jsonlLines.join('\n'), encoding: utf8);

    final int now = DateTime.now().millisecondsSinceEpoch;
    final Book book = Book(
      id: bookId,
      title: parsed.title,
      author: parsed.author,
      format: p.extension(sourcePath).replaceFirst('.', ''),
      contentPath: contentFile.path,
      chapterCount: chapters.length,
      totalChars: parsed.totalChars,
      fileSize: await File(sourcePath).length(),
      createdAt: now,
      updatedAt: now,
    );

    await _bookDao.insert(book);
    await _chapterDao.replaceAll(bookId, chapters);
    await _progressDao.upsert(ReadingProgress(
      bookId: bookId,
      chapterIndex: 0,
      paragraphIndex: 0,
      lineIndex: 0,
      percent: 0,
      updatedAt: now,
    ));
    return book;
  }

  /// 删书：同时清掉正文文件、章节、进度、书签、笔记。
  Future<void> deleteBook(String bookId) async {
    await _bookDao.delete(bookId);
    await _chapterDao.replaceAll(bookId, <Chapter>[]);
    await _progressDao.deleteByBook(bookId);
    await _annotationRepository.deleteByBook(bookId);

    final Directory bookDir = Directory(p.join((await _booksRoot()).path, bookId));
    if (await bookDir.exists()) {
      await bookDir.delete(recursive: true);
    }
  }

  Future<Directory> _ensureBookDir(String bookId) async {
    final Directory dir = Directory(p.join((await _booksRoot()).path, bookId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _booksRoot() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(support.path, 'books'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
