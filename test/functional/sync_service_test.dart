import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/models/bookmark.dart';
import 'package:novel_reader/models/note.dart';
import 'package:novel_reader/models/reading_progress.dart';
import 'package:novel_reader/services/sync/sync_service.dart';
import 'package:novel_reader/services/sync/sync_transports.dart';

import 'test_support.dart';

/// 同步合并逻辑功能测试（FT-SYNC 系列）。
/// last-write-wins 语义、畸形对端数据过滤、书签合并一致性。
void main() {
  group('FT-SYNC 同步', () {
    late TestHarness harness;

    setUp(() async {
      harness = await createHarness();
    });

    tearDown(() async {
      await harness.dispose();
    });

    ReadingProgress progress(String bookId,
            {int chapter = 0, int paragraph = 0, int line = 0, int updatedAt = 1000}) =>
        ReadingProgress(
          bookId: bookId,
          chapterIndex: chapter,
          paragraphIndex: paragraph,
          lineIndex: line,
          percent: 0.5,
          updatedAt: updatedAt,
        );

    test('FT-SYNC-01 对端无数据（download 返回 null）时零拉取且不崩溃', () async {
      await harness.syncService.sync('device-A', _FakeTransport(remote: null));
      // DEF-06 修复后 download 返回 null 也会上传本地全量（首同步自举），
      // 但拉取计数仍为零。上传行为见 FT-SYNC-07a。
      final SyncReport report =
          await harness.syncService.sync('device-A', _FakeTransport(remote: null));
      expect(report.pulledProgress, 0);
      expect(report.pulledBookmarks, 0);
      expect(report.pulledNotes, 0);
    });

    test('FT-SYNC-02 进度 last-write-wins：对端更新则覆盖，对端更旧则保留', () async {
      await harness.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      final String bookId =
          (await harness.database.query('books')).first['id'] as String;

      // 对端更新（updated_at 更大）→ 覆盖
      final SyncReport r1 = await harness.syncService.sync(
        'device-A',
        _FakeTransport(remote: SyncPayload(
          deviceId: 'device-B',
          progressList: <ReadingProgress>[
            progress(bookId, chapter: 2, paragraph: 3, updatedAt: 9000000000000),
          ],
          bookmarks: <Bookmark>[],
          notes: <ReadingNote>[],
        )),
      );
      expect(r1.pulledProgress, 1);
      final ReadingProgress? after1 =
          await harness.readerRepository.loadProgress(bookId);
      expect(after1!.chapterIndex, 2);

      // 对端更旧（updated_at 更小）→ 不覆盖
      final SyncReport r2 = await harness.syncService.sync(
        'device-A',
        _FakeTransport(remote: SyncPayload(
          deviceId: 'device-B',
          progressList: <ReadingProgress>[
            progress(bookId, chapter: 1, updatedAt: 1000),
          ],
          bookmarks: <Bookmark>[],
          notes: <ReadingNote>[],
        )),
      );
      expect(r2.pulledProgress, 0);
      final ReadingProgress? after2 =
          await harness.readerRepository.loadProgress(bookId);
      expect(after2!.chapterIndex, 2, reason: '更旧的对端进度不得覆盖本地');
    });

    test('FT-SYNC-03 笔记 last-write-wins：按 updated_at 覆盖或保留', () async {
      const ReadingNote remoteNew = ReadingNote(
        id: 'note-remote',
        bookId: 'book-x',
        chapterIndex: 0,
        paragraphIndex: 0,
        lineIndex: 0,
        chapterTitle: '第一章',
        selectedText: '原文',
        content: '对端新内容',
        createdAt: 1000,
        updatedAt: 5000,
      );
      final SyncReport r1 = await harness.syncService.sync(
        'device-A',
        _FakeTransport(remote: const SyncPayload(
          deviceId: 'device-B',
          progressList: <ReadingProgress>[],
          bookmarks: <Bookmark>[],
          notes: <ReadingNote>[remoteNew],
        )),
      );
      expect(r1.pulledNotes, 1);

      // 同 id 更旧内容 → 保留本地
      final ReadingNote remoteOld = remoteNew.copyWith(
        content: '对端旧内容',
        updatedAt: 1000,
      );
      final SyncReport r2 = await harness.syncService.sync(
        'device-A',
        _FakeTransport(remote: SyncPayload(
          deviceId: 'device-B',
          progressList: <ReadingProgress>[],
          bookmarks: <Bookmark>[],
          notes: <ReadingNote>[remoteOld],
        )),
      );
      expect(r2.pulledNotes, 0);
      final List<Map<String, Object?>> rows =
          await harness.database.query('notes', where: 'id = ?', whereArgs: <Object?>['note-remote']);
      expect(rows.first['content'], '对端新内容');
    });

    test('FT-SYNC-04 书签合并 last-write-wins：对端更新则覆盖，对端更旧则保留', () async {
      const Bookmark local = Bookmark(
        id: 'bm-shared',
        bookId: 'book-x',
        chapterIndex: 0,
        paragraphIndex: 0,
        lineIndex: 0,
        chapterTitle: '第一章',
        excerpt: '原文',
        comment: '本地短评',
        createdAt: 1000,
        updatedAt: 1000,
      );
      await harness.annotationRepository.addBookmark(local);

      // 对端更新（updated_at 更大）→ 覆盖本地
      const Bookmark remoteNewer = Bookmark(
        id: 'bm-shared',
        bookId: 'book-x',
        chapterIndex: 0,
        paragraphIndex: 0,
        lineIndex: 0,
        chapterTitle: '第一章',
        excerpt: '原文',
        comment: '对端短评',
        createdAt: 1000,
        updatedAt: 5000,
      );
      final SyncReport r1 = await harness.syncService.sync(
        'device-A',
        _FakeTransport(remote: const SyncPayload(
          deviceId: 'device-B',
          progressList: <ReadingProgress>[],
          bookmarks: <Bookmark>[remoteNewer],
          notes: <ReadingNote>[],
        )),
      );
      expect(r1.pulledBookmarks, 1);
      List<Map<String, Object?>> rows = await harness.database
          .query('bookmarks', where: 'id = ?', whereArgs: <Object?>['bm-shared']);
      expect(rows.first['comment'], '对端短评');

      // 对端更旧（updated_at 更小）→ 保留本地
      const Bookmark remoteOlder = Bookmark(
        id: 'bm-shared',
        bookId: 'book-x',
        chapterIndex: 0,
        paragraphIndex: 0,
        lineIndex: 0,
        chapterTitle: '第一章',
        excerpt: '原文',
        comment: '对端旧短评',
        createdAt: 1000,
        updatedAt: 2000,
      );
      final SyncReport r2 = await harness.syncService.sync(
        'device-A',
        _FakeTransport(remote: const SyncPayload(
          deviceId: 'device-B',
          progressList: <ReadingProgress>[],
          bookmarks: <Bookmark>[remoteOlder],
          notes: <ReadingNote>[],
        )),
      );
      expect(r2.pulledBookmarks, 0);
      rows = await harness.database
          .query('bookmarks', where: 'id = ?', whereArgs: <Object?>['bm-shared']);
      expect(rows.first['comment'], '对端短评',
          reason: 'DEF-03 修复：书签与笔记一样按 updated_at last-write-wins');
    });

    test('FT-SYNC-05 本地没有的书签被拉入', () async {
      const Bookmark remote = Bookmark(
        id: 'bm-new',
        bookId: 'book-x',
        chapterIndex: 1,
        paragraphIndex: 2,
        lineIndex: 0,
        chapterTitle: '第二章',
        excerpt: '对端摘录',
        comment: '',
        createdAt: 2000,
        updatedAt: 2000,
      );
      final SyncReport report = await harness.syncService.sync(
        'device-A',
        _FakeTransport(remote: const SyncPayload(
          deviceId: 'device-B',
          progressList: <ReadingProgress>[],
          bookmarks: <Bookmark>[remote],
          notes: <ReadingNote>[],
        )),
      );
      expect(report.pulledBookmarks, 1);
    });

    test('FT-SYNC-06a device_id 为非 String 时回落 unknown-device', () async {
      // DEF-05 修复：对端可能是旧版本/第三方实现，device_id 不保证是 String
      final Map<String, Object?> badDeviceId = <String, Object?>{
        'device_id': 12345,
      };
      final SyncPayload payload = SyncPayload.fromJson(badDeviceId);
      expect(payload.deviceId, 'unknown-device');
    });

    test('FT-SYNC-06b 字段类型错误（String 递给 num 字段）回落默认值', () async {
      // DEF-08 修复：as T? 只防 null 不防类型错误，统一改 is 判断 + 默认值
      final Map<String, Object?> wrongType = <String, Object?>{
        'device_id': 'device-B',
        'bookmarks': <Object?>[
          <String, Object?>{'id': 'bm-ok', 'book_id': 'b', 'chapter_index': 'x'},
        ],
      };
      final SyncPayload payload = SyncPayload.fromJson(wrongType);
      expect(payload.bookmarks.length, 1);
      expect(payload.bookmarks.first.chapterIndex, 0);
    });

    test('FT-SYNC-06c 缺字段条目走安全默认值，非 Map 条目被过滤', () async {
      final Map<String, Object?> partial = <String, Object?>{
        'device_id': 'device-B',
        'progress': 'not-a-list', // 非 List → 空
        'bookmarks': <Object?>[
          'string-entry', // 非 Map → 过滤
          <String, Object?>{'id': 'bm-ok'}, // 其余字段全缺 → 安全默认值
        ],
        'notes': <Object?>[
          <String, Object?>{
            'id': 'note-ok',
            'book_id': 'b',
            'chapter_index': 1,
            'paragraph_index': 0,
            'line_index': 0,
            'chapter_title': '第一章',
            'selected_text': '原文',
            'content': '内容',
            'created_at': 1,
            'updated_at': 2,
          }
        ],
      };

      final SyncPayload payload = SyncPayload.fromJson(partial);
      expect(payload.deviceId, 'device-B');
      expect(payload.progressList, isEmpty);
      expect(payload.bookmarks.length, 1);
      expect(payload.bookmarks.first.id, 'bm-ok');
      expect(payload.bookmarks.first.bookId, '');
      expect(payload.notes.length, 1);

      // 经服务合并后不崩且写入容错后的条目
      final SyncReport report = await harness.syncService.sync(
        'device-A',
        _FakeTransport(remote: payload),
      );
      expect(report.pulledBookmarks, 1);
      expect(report.pulledNotes, 1);
    });

    test('FT-SYNC-07a 首同步（对端无数据）上传本地全量数据', () async {
      await harness.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      final _FakeTransport transport = _FakeTransport(remote: null);
      await harness.syncService.sync('device-A', transport);

      // DEF-06 修复：download 返回 null（首次配对/空端点）时也上传本地全量，
      // 否则两台新设备互相等对方先推，同步永远无法自举。
      expect(transport.uploaded, isNotNull);
      expect(transport.uploaded!.deviceId, 'device-A');
      expect(transport.uploaded!.progressList.length, 1,
          reason: '首同步应把本地进度播种到对端');
    });

    test('FT-SYNC-07b 对端有数据时上传合并后的本地全量数据', () async {
      await harness.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      final _FakeTransport transport = _FakeTransport(remote: const SyncPayload(
        deviceId: 'device-B',
        progressList: <ReadingProgress>[],
        bookmarks: <Bookmark>[],
        notes: <ReadingNote>[],
      ));
      await harness.syncService.sync('device-A', transport);

      expect(transport.uploaded, isNotNull);
      expect(transport.uploaded!.deviceId, 'device-A');
      expect(transport.uploaded!.progressList.length, 1,
          reason: '上传内容应为合并后的本地全量进度');
    });

    test('FT-SYNC-08 对端返回 JSON 数组时 download 抛可读 ImportException', () async {
      // 畸形服务端：HTTP 200 但 body 是 JSON 数组而非对象。
      // DEF-04 修复：传输层先 is Map 判断，非对象数据抛 ImportException
      // （书架同步入口 catch 后提示「同步失败：...」），本地数据不受影响。
      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write('[1,2,3]');
        await request.response.close();
      });
      try {
        final CloudSyncTransport transport = CloudSyncTransport(
          baseUrl: 'http://127.0.0.1:${server.port}',
          apiToken: 'token',
        );
        await expectLater(
          transport.download(),
          throwsA(isA<ImportException>()
              .having((ImportException e) => e.message, 'message', contains('格式不正确'))),
        );
      } finally {
        await server.close(force: true);
      }

      // 本地数据完好
      await harness.bookRepository.importFile(
          sampleBookPath('测试书1-雨夜听刀.txt'));
      final List<Map<String, Object?>> rows =
          await harness.database.query('books');
      expect(rows.length, 1);
    });
  });
}

/// 内存同步通道：download 返回预设对端包，upload 记录本地包。
class _FakeTransport implements SyncTransport {
  _FakeTransport({required this.remote});

  final SyncPayload? remote;
  SyncPayload? uploaded;

  @override
  Future<SyncPayload?> download() async => remote;

  @override
  Future<void> upload(SyncPayload payload) async {
    uploaded = payload;
  }
}
