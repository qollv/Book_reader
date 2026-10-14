import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

import 'package:novel_reader/core/import_exception.dart';

/// 书籍文本文件读取：按 BOM 判定 → UTF-8 → GBK/GB18030 回退。
///
/// 中文网络小说资源大量是 GBK 编码，直接按 UTF-8 读会抛
/// FileSystemException；二进制文件（误选 pdf/epub）也走同一路径。
Future<String> readBookText(String path) async {
  final Uint8List bytes = await File(path).readAsBytes();

  // UTF-8 BOM：剥掉再解码（File.readAsString 默认会吃掉，这里显式处理）
  if (_hasBom(bytes, const <int>[0xEF, 0xBB, 0xBF])) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  // UTF-16 LE/BE BOM
  if (_hasBom(bytes, const <int>[0xFF, 0xFE])) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (_hasBom(bytes, const <int>[0xFE, 0xFF])) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }

  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 回退 GBK/GB18030（纯 Dart 解码器，无 native 依赖）
    try {
      return gbk.decode(bytes);
    } catch (_) {
      throw const ImportException('文件编码不支持，请转换为 UTF-8 后重试');
    }
  }
}

bool _hasBom(Uint8List bytes, List<int> bom) {
  if (bytes.length < bom.length) {
    return false;
  }
  for (int i = 0; i < bom.length; i++) {
    if (bytes[i] != bom[i]) {
      return false;
    }
  }
  return true;
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i + 1 < bytes.length; i += 2) {
    final int code = littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1];
    buffer.writeCharCode(code);
  }
  return buffer.toString();
}
