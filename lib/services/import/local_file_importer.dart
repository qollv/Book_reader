import 'package:file_picker/file_picker.dart';

import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/data/repositories/book_repository.dart';
import 'package:novel_reader/models/book.dart';

/// 本地文件导入：系统文件选择器 → 解析入库。
class LocalFileImporter {
  LocalFileImporter(this._bookRepository);

  final BookRepository _bookRepository;

  static const List<String> supportedExtensions = <String>['txt', 'md', 'markdown', 'docx'];

  /// 返回 null 表示用户取消了选择。
  Future<Book?> pickAndImport() async {
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    if (file == null) {
      return null;
    }
    final String? path = file.path;
    if (path == null) {
      throw const ImportException('无法读取所选文件');
    }
    return _bookRepository.importFile(path);
  }
}
