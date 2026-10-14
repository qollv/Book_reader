import 'package:file_picker/file_picker.dart';

import 'package:novel_reader/data/repositories/book_repository.dart';
import 'package:novel_reader/models/book.dart';

/// 导入异常：对外统一用中文可读信息。
class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => 'ImportException: $message';
}

/// 本地文件导入：系统文件选择器 → 解析入库。
class LocalFileImporter {
  LocalFileImporter(this._bookRepository);

  final BookRepository _bookRepository;

  static const List<String> supportedExtensions = <String>['txt', 'md', 'markdown', 'docx'];

  /// 返回 null 表示用户取消了选择。
  Future<Book?> pickAndImport() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowedExtensions: supportedExtensions,
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final String? path = result.files.single.path;
    if (path == null) {
      throw const ImportException('无法读取所选文件');
    }
    return _bookRepository.importFile(path);
  }
}
