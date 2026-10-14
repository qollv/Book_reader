import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/parsers/parsed_book.dart';
import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/models/bookmark.dart';
import 'package:novel_reader/models/chapter.dart';
import 'package:novel_reader/models/note.dart';
import 'package:novel_reader/models/reading_progress.dart';

// TC-13：DEF-16 反序列化硬转型。外部同步数据（int percent）/ 损坏库曾致崩溃。
void main() {
  test('ReadingProgress 容忍 int percent 与缺字段', () {
    final ReadingProgress progress = ReadingProgress.fromRow(<String, Object?>{
      'book_id': 'b1',
      'chapter_index': 1,
      'paragraph_index': 0,
      'line_index': 0,
      'percent': 0, // int 而非 double
      'updated_at': 123,
    });
    expect(progress.percent, 0.0);

    final ReadingProgress partial = ReadingProgress.fromRow(<String, Object?>{'book_id': 'b1'});
    expect(partial.chapterIndex, 0);
    expect(partial.percent, 0.0);
  });

  test('ParagraphBlock 缺 level 不崩', () {
    final ParagraphBlock block = ParagraphBlock.fromJson(<String, Object?>{
      'text': '正文',
      'kind': 'paragraph',
    });
    expect(block.headingLevel, 1);
    expect(block.text, '正文');
  });

  test('Book / Chapter / Bookmark / ReadingNote 缺字段取安全默认值', () {
    expect(Book.fromRow(<String, Object?>{}).title, '');
    expect(Chapter.fromRow(<String, Object?>{}).index, 0);
    expect(Bookmark.fromRow(<String, Object?>{}).excerpt, '');
    expect(ReadingNote.fromRow(<String, Object?>{}).content, '');
  });
}
