import 'dart:convert';

import 'package:novel_reader/data/dao/bookmark_dao.dart';
import 'package:novel_reader/data/dao/note_dao.dart';
import 'package:novel_reader/data/dao/progress_dao.dart';
import 'package:novel_reader/models/bookmark.dart';
import 'package:novel_reader/models/note.dart';
import 'package:novel_reader/models/reading_progress.dart';
import 'package:novel_reader/services/sync/sync_transports.dart';

/// 同步数据包：进度 + 书签 + 笔记。
class SyncPayload {
  const SyncPayload({
    required this.deviceId,
    required this.progressList,
    required this.bookmarks,
    required this.notes,
  });

  final String deviceId;
  final List<ReadingProgress> progressList;
  final List<Bookmark> bookmarks;
  final List<ReadingNote> notes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'device_id': deviceId,
      'progress': progressList.map((ReadingProgress e) => e.toRow()).toList(),
      'bookmarks': bookmarks.map((Bookmark e) => e.toRow()).toList(),
      'notes': notes.map((ReadingNote e) => e.toRow()).toList(),
    };
  }

  static SyncPayload fromJson(Map<String, Object?> json) {
    return SyncPayload(
      deviceId: json['device_id'] as String,
      progressList: (json['progress'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(ReadingProgress.fromRow)
          .toList(),
      bookmarks: (json['bookmarks'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(Bookmark.fromRow)
          .toList(),
      notes: (json['notes'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(ReadingNote.fromRow)
          .toList(),
    );
  }
}

/// 同步结果统计，供界面提示。
class SyncReport {
  const SyncReport({required this.pulledProgress, required this.pulledBookmarks, required this.pulledNotes});

  final int pulledProgress;
  final int pulledBookmarks;
  final int pulledNotes;
}

/// 进度/书签/笔记同步。
///
/// 合并策略 last-write-wins：逐条按 updated_at 取较新者。
/// 删除操作不做传播（避免误删别人设备的数据），记录在案为已知限制。
class ProgressSyncService {
  ProgressSyncService({
    required ProgressDao progressDao,
    required BookmarkDao bookmarkDao,
    required NoteDao noteDao,
    required SyncTransport transport,
  }) : _progressDao = progressDao,
       _bookmarkDao = bookmarkDao,
       _noteDao = noteDao,
       _transport = transport;

  final ProgressDao _progressDao;
  final BookmarkDao _bookmarkDao;
  final NoteDao _noteDao;
  final SyncTransport _transport;

  Future<SyncReport> sync(String deviceId) async {
    final SyncPayload? remote = await _transport.download();
    if (remote == null) {
      return const SyncReport(pulledProgress: 0, pulledBookmarks: 0, pulledNotes: 0);
    }

    int pulledProgress = 0;
    int pulledBookmarks = 0;
    int pulledNotes = 0;

    for (ReadingProgress remoteProgress in remote.progressList) {
      final ReadingProgress? local = await _progressDao.findByBook(remoteProgress.bookId);
      if (local == null || remoteProgress.updatedAt > local.updatedAt) {
        await _progressDao.upsert(remoteProgress);
        pulledProgress++;
      }
    }
    for (Bookmark remoteBookmark in remote.bookmarks) {
      if (!await _bookmarkExists(remoteBookmark.id)) {
        await _bookmarkDao.insert(remoteBookmark);
        pulledBookmarks++;
      }
    }
    for (ReadingNote remoteNote in remote.notes) {
      final ReadingNote? local = await _noteDao.findById(remoteNote.id);
      if (local == null) {
        await _noteDao.insert(remoteNote);
        pulledNotes++;
      } else if (remoteNote.updatedAt > local.updatedAt) {
        await _noteDao.update(remoteNote);
        pulledNotes++;
      }
    }

    final SyncPayload local = SyncPayload(
      deviceId: deviceId,
      progressList: await _progressDao.findAll(),
      bookmarks: await _bookmarkDao.findAll(),
      notes: await _noteDao.findAll(),
    );
    await _transport.upload(local);
    return SyncReport(
      pulledProgress: pulledProgress,
      pulledBookmarks: pulledBookmarks,
      pulledNotes: pulledNotes,
    );
  }

  Future<bool> _bookmarkExists(String bookmarkId) async {
    final List<Bookmark> all = await _bookmarkDao.findAll();
    for (Bookmark bookmark in all) {
      if (bookmark.id == bookmarkId) {
        return true;
      }
    }
    return false;
  }
}

/// 设备 ID：首次生成后持久化（SharedPreferences 由上层注入）。
String extractDeviceId(String raw) {
  if (raw.isEmpty) {
    return 'unknown-device';
  }
  try {
    final Map<String, Object?> json = jsonDecode(raw) as Map<String, Object?>;
    final Object? id = json['device_id'];
    if (id is String && id.isNotEmpty) {
      return id;
    }
  } on FormatException {
    return raw;
  }
  return 'unknown-device';
}
