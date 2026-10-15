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
    final String text = utf8.decode(bytes.sublist(3), allowMalformed: true);
    _checkText(text);
    return text;
  }
  // UTF-16 LE/BE BOM
  if (_hasBom(bytes, const <int>[0xFF, 0xFE])) {
    final String text = _decodeUtf16(bytes.sublist(2), littleEndian: true);
    _checkText(text);
    return text;
  }
  if (_hasBom(bytes, const <int>[0xFE, 0xFF])) {
    final String text = _decodeUtf16(bytes.sublist(2), littleEndian: false);
    _checkText(text);
    return text;
  }

  try {
    final String text = utf8.decode(bytes);
    _checkText(text);
    return text;
  } on FormatException {
    // 回退 GBK/GB18030（纯 Dart 解码器，无 native 依赖）
    try {
      final String text = gbk.decode(bytes);
      _checkText(text);
      return text;
    } catch (_) {
      throw const ImportException('文件编码不支持，请转换为 UTF-8 后重试');
    }
  }
}

/// 解码后校验：控制字符（\t\n\r 除外）占比过高说明是二进制文件误选。
/// 纯 ASCII 二进制（字节全 < 0x80）能通过 UTF-8 解码，只能靠这一步拦下。
void _checkText(String text) {
  if (text.isEmpty) {
    return;
  }
  int controlCount = 0;
  for (int i = 0; i < text.length; i++) {
    final int code = text.codeUnitAt(i);
    final bool isAllowedWhitespace = code == 0x09 || code == 0x0A || code == 0x0D;
    if (code < 0x20 && !isAllowedWhitespace) {
      controlCount++;
    } else if (code == 0x7F) {
      controlCount++;
    }
  }
  if (controlCount / text.length > 0.05) {
    throw const ImportException('文件内容异常，疑似二进制文件，请选择 txt/md/docx 书籍');
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
