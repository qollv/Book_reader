import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'package:novel_reader/data/repositories/book_repository.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/services/import/local_file_importer.dart';

/// URL 导入：http/https 直链下载到临时目录后走本地导入管线。
///
/// 安全约束：只允许 http/https；扩展名白名单；大小上限，防止把手机存爆。
class UrlImporter {
  UrlImporter(this._bookRepository);

  final BookRepository _bookRepository;

  static const int maxFileBytes = 100 * 1024 * 1024; // 100MB

  final Dio _dio = Dio();

  Future<Book> importFromUrl(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      throw const ImportException('链接格式不正确');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const ImportException('只支持 http/https 链接');
    }
    final String extension = p.extension(uri.path).replaceFirst('.', '').toLowerCase();
    if (!LocalFileImporter.supportedExtensions.contains(extension)) {
      throw const ImportException('只支持 txt / md / docx 文件');
    }

    final Directory tempDir = await Directory.systemTemp.createTemp('novel_dl_');
    try {
      final String savePath = p.join(tempDir.path, 'download.$extension');
      await _dio.download(
        url.trim(),
        savePath,
        options: Options(headers: <String, Object?>{HttpHeaders.userAgentHeader: 'novel-reader/0.1'}),
        onReceiveProgress: onProgress,
      );
      final int size = await File(savePath).length();
      if (size > maxFileBytes) {
        throw const ImportException('文件超过 100MB 上限');
      }
      return await _bookRepository.importFile(savePath);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}
