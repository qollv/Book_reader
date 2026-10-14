import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/txt_parser.dart';

// TC-04：DEF-12 书名行删除。前导空行曾把删除配额耗尽，导致书名残留并与正文粘连。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('txt_title_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<List<String>> firstBlocks(String raw) async {
    final File file = File('${tempDir.path}/t.txt');
    await file.writeAsString(raw, encoding: utf8);
    final book = await TxtParser().parseFile(file.path);
    return book.chapters.first.blocks.map((block) => block.text).toList();
  }

  test('四种书名排版下正文首段均为正文一。', () async {
    expect(await firstBlocks('无名小说\n正文一。\n正文二。'), <String>['正文一。', '正文二。']);
    expect(await firstBlocks('\n无名小说\n正文一。\n正文二。'), <String>['正文一。', '正文二。']);
    expect(await firstBlocks('\n\n无名小说\n正文一。\n正文二。'), <String>['正文一。', '正文二。']);
    expect(await firstBlocks('无名小说\n\n正文一。\n正文二。'), <String>['正文一。', '正文二。']);
  });
}
