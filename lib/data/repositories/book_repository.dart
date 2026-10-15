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
///
/// 「本地文件导入」与「在线源整本导入」共用 [importBlocks] 一条路径，
/// 于是阅读器/分页/进度/书签对两类书完全一致，不需要分支。
class BookRepository {
  BookRepository({
    required BookDao bookDao,
    required ChapterDao chapterDao,
    required ProgressDao progressDao,
    required AnnotationRepository annotationRepository,
    Future<Directory> Function()? supportDirectory,
  }) : _bookDao = bookDao,
       _chapterDao = chapterDao,
       _progressDao = progressDao,
       _annotationRepository = annotationRepository,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final BookDao _bookDao;
  final ChapterDao _chapterDao;
  final ProgressDao _progressDao;
  final AnnotationRepository _annotationRepository;

  /// 书籍根目录的父目录。生产用 path_provider，测试注入临时目录——
  /// 否则 DAO 与导入管线只能在真机上测。
  final Future<Directory> Function() _supportDirectory;

  BookDao get bookDao => _bookDao;

  /// 从本地文件导入一本书。解析失败时向外抛异常，不留下半成品。
  Future<Book> importFile(String sourcePath) async {
    final BookParser parser = parserForFile(sourcePath);
    final ParsedBook parsed = await parser.parseFile(sourcePath);
    final File file = File(sourcePath);
    return importBlocks(
      title: parsed.title,
      author: parsed.author,
      // 在线源导入用 'online'，本地导入用扩展名，便于书架区分与排查
      format: p.extension(sourcePath).replaceFirst('.', ''),
      chapters: parsed.chapters,
      fileSize: await file.exists() ? await file.length() : 0,
    );
  }

  /// 把已经解析好的章节写入书架。
  ///
  /// 在线源整本导入走的也是这里：先把所有章节抓成 [ParsedChapter]，
  /// 再一次性落盘——避免抓一半失败时留下半本书（上游的 CacheBookWork
  /// 是逐章写库，中途失败会留下「部分缓存」的中间态）。
  Future<Book> importBlocks({
    required String title,
    required String author,
    required String format,
    required List<ParsedChapter> chapters,
    int fileSize = 0,
    String sourceId = '',
    String sourceBookId = '',
    String coverUrl = '',
    String? bookId,
  }) async {
    final String id = bookId ?? const Uuid().v4();
    final Directory bookDir = await ensureBookDir(id);
    final File contentFile = File(p.join(bookDir.path, 'content.jsonl'));
    final File tempFile = File('${contentFile.path}.tmp');

    final List<Chapter> chapterRows = <Chapter>[];
    final List<String> jsonlLines = <String>[];
    int paragraphCursor = 0;
    int totalChars = 0;

    for (int i = 0; i < chapters.length; i++) {
      final ParsedChapter parsedChapter = chapters[i];
      for (final ParagraphBlock block in parsedChapter.blocks) {
        jsonlLines.add(jsonEncode(block.toJson()));
        totalChars += block.text.length;
      }
      chapterRows.add(Chapter(
        bookId: id,
        index: i,
        title: parsedChapter.title,
        paragraphStart: paragraphCursor,
        paragraphEnd: paragraphCursor + parsedChapter.blocks.length,
      ));
      paragraphCursor += parsedChapter.blocks.length;
    }

    // 先写临时文件再改名：进程被杀不会留下截断的 content.jsonl
    await tempFile.writeAsString(jsonlLines.join('\n'), encoding: utf8);
    await tempFile.rename(contentFile.path);

    final int now = DateTime.now().millisecondsSinceEpoch;
    final Book book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      contentPath: contentFile.path,
      chapterCount: chapterRows.length,
      totalChars: totalChars,
      fileSize: fileSize > 0 ? fileSize : await contentFile.length(),
      createdAt: now,
      updatedAt: now,
      sourceId: sourceId,
      sourceBookId: sourceBookId,
      coverUrl: coverUrl,
    );

    await _bookDao.insert(book);
    await _chapterDao.replaceAll(id, chapterRows);
    await _progressDao.upsert(ReadingProgress(
      bookId: id,
      chapterIndex: 0,
      paragraphIndex: 0,
      lineIndex: 0,
      percent: 0,
      updatedAt: now,
    ));
    return book;
  }

  /// 按 (源, 源内 id) 找书架里已有的书，用于导入去重。
  Future<Book?> findBySource(String sourceId, String sourceBookId) async {
    if (sourceId.isEmpty || sourceBookId.isEmpty) {
      return null;
    }
    final List<Book> all = await _bookDao.findAll();
    for (final Book book in all) {
      if (book.sourceId == sourceId && book.sourceBookId == sourceBookId) {
        return book;
      }
    }
    return null;
  }

  /// 删书：同时清掉正文文件、章节、进度、书签、笔记。
  Future<void> deleteBook(String bookId) async {
    await _bookDao.delete(bookId);
    await _chapterDao.replaceAll(bookId, <Chapter>[]);
    await _progressDao.deleteByBook(bookId);
    await _annotationRepository.deleteByBook(bookId);

    final Directory bookDir = Directory(p.join((await booksRoot()).path, bookId));
    if (await bookDir.exists()) {
      await bookDir.delete(recursive: true);
    }
  }

  Future<Directory> ensureBookDir(String bookId) async {
    final Directory dir = Directory(p.join((await booksRoot()).path, bookId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> booksRoot() async {
    final Directory support = await _supportDirectory();
    final Directory dir = Directory(p.join(support.path, 'books'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 存储审计：书籍根目录下所有正文文件的总字节数。
  Future<int> contentBytes() async {
    final Directory root = await booksRoot();
    int total = 0;
    await for (final FileSystemEntity entity in root.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
