import 'dart:io';

/// 书籍文件被拒（扩展名不支持 / 太大 / 不是文本）。
///
/// [toString] 直接返回可展示的中文原因：导入链路的错误最终会显示给用户，
/// 不该让用户看到 `FileSystemException: ... utf-8` 这种内部信息。
class BookFileRejected implements Exception {
  const BookFileRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 允许导入的扩展名。**白名单而非黑名单**：未知扩展名不再按 txt 兜底，
/// 否则用户误选一个 pdf 会被当成文本解析，报出的错还和文件类型无关。
const Set<String> kSupportedBookExtensions = <String>{
  'txt',
  'text',
  'md',
  'markdown',
  'docx',
};

/// 单文件大小上限（100 MB）。对应计划书里的「防滥用」约定。
const int kMaxBookFileBytes = 100 * 1024 * 1024;

/// 导入前的静态体检：扩展名、存在性、大小、非空。
///
/// 放在解析器之前统一拦截，好处是三个解析器共享同一套边界条件，
/// 不会各写一份、各漏一条。
Future<File> checkBookFile(String path) async {
  final File file = File(path);
  if (!await file.exists()) {
    throw const BookFileRejected('文件不存在或已被移动');
  }

  final String name = file.uri.pathSegments.last;
  final int dot = name.lastIndexOf('.');
  final String ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  if (!kSupportedBookExtensions.contains(ext)) {
    throw BookFileRejected(
      '不支持的文件类型「${ext.isEmpty ? name : ext}」，目前支持 '
      '${kSupportedBookExtensions.join(' / ')}',
    );
  }

  final int size = await file.length();
  if (size == 0) {
    throw const BookFileRejected('文件是空的');
  }
  if (size > kMaxBookFileBytes) {
    throw BookFileRejected(
      '文件太大（${(size / 1024 / 1024).toStringAsFixed(1)} MB），'
      '上限 ${kMaxBookFileBytes ~/ 1024 ~/ 1024} MB',
    );
  }
  return file;
}
