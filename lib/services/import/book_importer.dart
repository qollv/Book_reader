import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/services/import/local_file_importer.dart';
import 'package:novel_reader/services/import/url_importer.dart';

/// 统一导入入口：本地文件 + URL 直链。
class BookImporter {
  BookImporter({required LocalFileImporter localImporter, required UrlImporter urlImporter})
      : _localImporter = localImporter,
        _urlImporter = urlImporter;

  final LocalFileImporter _localImporter;
  final UrlImporter _urlImporter;

  /// 返回 null 表示用户在文件选择器中取消。
  Future<Book?> pickLocal() {
    return _localImporter.pickAndImport();
  }

  Future<Book> fromUrl(String url, {void Function(int received, int total)? onProgress}) {
    return _urlImporter.importFromUrl(url, onProgress: onProgress);
  }
}
