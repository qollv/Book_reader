import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

/// 解码结果：文本 + 实际使用的编码（便于诊断与测试断言）。
class DecodedText {
  const DecodedText(this.text, this.encoding);

  final String text;

  /// 实际生效的编码名，如 `utf-8` / `utf-8-bom` / `gbk` / `utf-16le`。
  final String encoding;

  @override
  String toString() => 'DecodedText($encoding, ${text.length} 字符)';
}

/// 书籍文件解码失败（编码无法识别、或看起来不是文本文件）。
class TextDecodeException implements Exception {
  const TextDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// UTF-16 无 BOM 时用来判断字节序的启发式阈值。
const double _binaryNulRatioThreshold = 0.30;

/// 判定为二进制前最多检查多少字节。
const int _sniffWindow = 8192;

/// 按 BOM 判断编码并解码；无 BOM 返回 null。
DecodedText? decodeWithBom(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return DecodedText(
      utf8.decode(bytes.sublist(3), allowMalformed: true),
      'utf-8-bom',
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return DecodedText(_decodeUtf16(bytes.sublist(2), littleEndian: true), 'utf-16le');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return DecodedText(_decodeUtf16(bytes.sublist(2), littleEndian: false), 'utf-16be');
  }
  return null;
}

/// 用**声明的**编码解码（在线源走这条：站点声明什么就用什么，不猜）。
///
/// 与 [decodeBookFileBytes] 的区别：声明了编码就不做回退猜测——
/// 猜出来的编码和站点声明不一致时，乱码比报错更难排查。
String decodeWithCharset(List<int> bytes, String charset) {
  final String name = charset.trim().toLowerCase();
  if (name.isEmpty || name == 'auto' || name == 'detect') {
    return decodeBookFileBytes(Uint8List.fromList(bytes)).text;
  }
  if (name == 'utf-8' || name == 'utf8') {
    return decodeLenient(utf8, bytes);
  }
  final Encoding? encoding = Charset.getByName(name);
  if (encoding == null) {
    return decodeLenient(utf8, bytes);
  }
  return decodeLenient(encoding, bytes);
}

/// 该编码名是否被支持。
bool isKnownCharsetName(String charset) {
  final String name = charset.trim().toLowerCase();
  if (name == 'auto' || name == 'detect' || name == 'utf-8' || name == 'utf8') {
    return true;
  }
  return Charset.getByName(name) != null;
}

/// 按声明编码解码；失败时容错解码而不是抛异常。
String decodeLenient(Encoding encoding, List<int> bytes) {
  try {
    return encoding.decode(bytes);
  } on FormatException {
    return utf8.decode(bytes, allowMalformed: true);
  } on ArgumentError {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// 解码**书籍文件**的字节：BOM → 严格 UTF-8 → GBK 回退。
///
/// 为什么需要它：中文小说的 txt 大量是 ANSI/GBK（或带 BOM 的 UTF-8），
/// 而原先的实现是 `File(...).readAsString(encoding: utf8)` 写死 UTF-8，
/// GBK 文件直接抛 `FileSystemException: Failed to decode data using encoding 'utf-8'`，
/// 用户看到的是一个和「编码」毫无关系的报错。
///
/// 顺序也有讲究：**先严格 UTF-8**。因为合法 UTF-8 里不会出现非法字节序列，
/// 而几乎任何字节序列在 GBK 下都能解出「看起来像字」的东西——
/// 先猜 GBK 会把正常的 UTF-8 中文解成乱码。
DecodedText decodeBookFileBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const TextDecodeException('文件是空的');
  }
  if (looksBinary(bytes)) {
    throw const TextDecodeException(
      '这个文件看起来不是文本（可能是 PDF、图片或压缩包），请选择 txt / md / docx',
    );
  }

  final DecodedText? bom = decodeWithBom(bytes);
  if (bom != null) {
    return bom;
  }

  try {
    return DecodedText(utf8.decode(bytes), 'utf-8');
  } on FormatException {
    // 不是合法 UTF-8：中文老书最常见的就是 GBK/GB18030
    final String gbkText;
    try {
      gbkText = gbk.decode(bytes);
    } on FormatException {
      throw const TextDecodeException('无法识别文件编码（既不是 UTF-8 也不是 GBK/GB18030）');
    } on ArgumentError {
      throw const TextDecodeException('无法识别文件编码（既不是 UTF-8 也不是 GBK/GB18030）');
    }
    return DecodedText(gbkText, 'gbk');
  }
}

/// 看起来是不是二进制内容。
///
/// 判据是 NUL 字节占比：正常文本（含 UTF-8/GBK 中文）几乎不会出现 0x00，
/// 而 PDF、ELF、zip、图片在头部就有一堆。
bool looksBinary(Uint8List bytes) {
  final int window = bytes.length < _sniffWindow ? bytes.length : _sniffWindow;
  if (window == 0) {
    return false;
  }
  int nul = 0;
  for (int i = 0; i < window; i++) {
    if (bytes[i] == 0) {
      nul++;
    }
  }
  return nul / window > _binaryNulRatioThreshold;
}

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  final List<int> codeUnits = <int>[];
  for (int i = 0; i + 1 < bytes.length; i += 2) {
    codeUnits.add(littleEndian
        ? (bytes[i] | (bytes[i + 1] << 8))
        : ((bytes[i] << 8) | bytes[i + 1]));
  }
  return String.fromCharCodes(codeUnits);
}
