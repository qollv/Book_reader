import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/core/parsers/txt_parser.dart';

// TC-03：DEF-05 编码回退。中文网文大量 GBK 编码，直接按 UTF-8 读会抛
// FileSystemException；二进制文件（误选 pdf）应得到中文业务异常。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('encoding_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeBytes(String name, List<int> bytes) async {
    final File file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('GBK 编码 txt 正确解析出中文', () async {
    // 「第一章 起风了\n正文一。」的 GBK 字节
    final Uint8List gbkBytes = Uint8List.fromList(<int>[
      0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2, 0x20, 0xC6, 0xF0, 0xB7, 0xE7, 0xC1, 0xCB,
      0x0A, 0xD5, 0xFD, 0xCE, 0xC4, 0xD2, 0xBB, 0xA1, 0xA3,
    ]);
    final File file = await writeBytes('gbk.txt', gbkBytes);

    final book = await TxtParser().parseFile(file.path);
    expect(book.title, '第一章 起风了');
    expect(book.chapters.first.blocks.first.text, '正文一。');
  });

  test('UTF-8 BOM 书名干净', () async {
    final File file = await writeBytes(
      'bom.txt',
      <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('书名\n正文一。')],
    );
    final book = await TxtParser().parseFile(file.path);
    expect(book.title, '书名');
    expect(book.title.codeUnits.first, 0x4E66); // '书'，无 BOM 残留
  });

  test('二进制文件抛 ImportException 而非 FileSystemException', () async {
    final File file = await writeBytes('binary.bin', <int>[0x25, 0x50, 0x44, 0x46, 0x00, 0xFF, 0xFE, 0x80]);
    expect(
      () => TxtParser().parseFile(file.path),
      throwsA(isA<ImportException>()),
    );
  });
}
