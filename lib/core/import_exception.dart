/// 导入业务异常：对外统一用中文可读信息。
class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => 'ImportException: $message';
}
