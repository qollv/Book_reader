import 'package:novel_reader/core/parsers/parsed_book.dart';

/// 源里的一本书（搜索结果 / 探索列表项）。
///
/// `bookId` 是**源自己的 id**（如 `12345`），不是本地书架 id；
/// 只有导入书架时才分配本地 id，并用 (sourceId, bookId) 做幂等去重。
class SourceBook {
  const SourceBook({
    required this.sourceId,
    required this.bookId,
    required this.title,
    this.author = '',
    this.coverUrl = '',
    this.description = '',
    this.tags = const <String>[],
    this.isComplete,
  });

  final String sourceId;
  final String bookId;
  final String title;
  final String author;
  final String coverUrl;
  final String description;
  final List<String> tags;
  final bool? isComplete;

  /// 全局唯一键，用于「这本书是否已在书架里」的判断。
  String get uniqueKey => '$sourceId:$bookId';

  SourceBook copyWith({String? title, String? author, String? coverUrl, String? description}) {
    return SourceBook(
      sourceId: sourceId,
      bookId: bookId,
      title: title ?? this.title,
      author: author ?? this.author,
      coverUrl: coverUrl ?? this.coverUrl,
      description: description ?? this.description,
      tags: tags,
      isComplete: isComplete,
    );
  }

  /// 用另一份数据补全自己：对方非空的字段胜出，空字段保留自己的。
  ///
  /// 场景是「列表项 + 详情页」——搜索结果常常提供了标签、封面或简介，
  /// 而详情页可能只给出其中一部分。直接整体替换会把这些信息弄丢
  /// （实际就是这么丢过一次标签），所以这里按字段合并。
  SourceBook merge(SourceBook other) {
    return SourceBook(
      sourceId: sourceId.isNotEmpty ? sourceId : other.sourceId,
      bookId: bookId.isNotEmpty ? bookId : other.bookId,
      title: other.title.isNotEmpty ? other.title : title,
      author: other.author.isNotEmpty ? other.author : author,
      coverUrl: other.coverUrl.isNotEmpty ? other.coverUrl : coverUrl,
      description: other.description.isNotEmpty ? other.description : description,
      tags: other.tags.isNotEmpty ? other.tags : tags,
      isComplete: other.isComplete ?? isComplete,
    );
  }
}

/// 源里的一章。
class SourceChapter {
  const SourceChapter({required this.id, required this.title});

  final String id;
  final String title;
}

/// 源里的一卷（没有分卷的源只有一卷，title 为空）。
class SourceVolume {
  const SourceVolume({required this.title, required this.chapters});

  final String title;
  final List<SourceChapter> chapters;
}

/// 书目详情：基本信息 + 目录。
class SourceBookDetail {
  const SourceBookDetail({required this.book, required this.volumes});

  final SourceBook book;
  final List<SourceVolume> volumes;

  List<SourceChapter> get chapters =>
      <SourceChapter>[for (final SourceVolume v in volumes) ...v.chapters];
}

/// 已解析的章节正文。
class SourceChapterContent {
  const SourceChapterContent({
    required this.id,
    required this.title,
    required this.blocks,
    this.prevId,
    this.nextId,
  });

  final String id;
  final String title;
  final List<ParagraphBlock> blocks;
  final String? prevId;
  final String? nextId;

  int get charCount {
    int n = 0;
    for (final ParagraphBlock b in blocks) {
      n += b.text.length;
    }
    return n;
  }
}

/// 搜索流的事件类型。
///
/// 语义照搬上游 `SearchResult` 的 sealed class：搜索是一个**事件流**而不是
/// 一次性返回值——单本命中可以立刻跳详情，多本结果逐条追加，
/// 分页过程允许部分成功后再报错。
enum SourceSearchEventKind { book, empty, end, error }

/// 搜索流的一条事件。
class SourceSearchEvent {
  const SourceSearchEvent._(this.kind, {this.book, this.message});

  const SourceSearchEvent.book(SourceBook book) : this._(SourceSearchEventKind.book, book: book);

  const SourceSearchEvent.empty() : this._(SourceSearchEventKind.empty);

  const SourceSearchEvent.end() : this._(SourceSearchEventKind.end);

  const SourceSearchEvent.error(String message) : this._(SourceSearchEventKind.error, message: message);

  final SourceSearchEventKind kind;
  final SourceBook? book;
  final String? message;
}
