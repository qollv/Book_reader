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
      // 对端可能是旧版本/第三方实现，device_id 不保证是 String
      deviceId: json['device_id'] is String ? json['device_id'] as String : 'unknown-device',
      progressList: _rows(json['progress']).map(ReadingProgress.fromRow).toList(),
      bookmarks: _rows(json['bookmarks']).map(Bookmark.fromRow).toList(),
      notes: _rows(json['notes']).map(ReadingNote.fromRow).toList(),
    );
  }

  /// 同步数据来自对端设备，逐条过滤掉结构不符的条目而非整体崩溃。
  static List<Map<String, Object?>> _rows(Object? value) {
    if (value is! List<Object?>) {
      return <Map<String, Object?>>[];
    }
    return value.whereType<Map<String, Object?>>().toList();
  }
}

/// 同步结果统计，供界面提示。
class SyncReport {
  const SyncReport({required this.pulledProgress, required this.pulledBookmarks, required this.pulledNotes});

  final int pulledProgress;
  final int pulledBookmarks;
  final int pulledNotes;
}

/// 进度/书签/笔记同步服务。
///
/// 传输通道在每次 sync 调用时传入：用户可在设置里配置云端端点，
/// 或在局域网配对后切到 LanSyncTransport，服务本身不绑定具体通道。
class ProgressSyncService {
  ProgressSyncService({
    required ProgressDao progressDao,
    required BookmarkDao bookmarkDao,
    required NoteDao noteDao,
  }) : _progressDao = progressDao,
       _bookmarkDao = bookmarkDao,
       _noteDao = noteDao;

  final ProgressDao _progressDao;
  final BookmarkDao _bookmarkDao;
  final NoteDao _noteDao;

  /// 合并策略 last-write-wins：进度/书签/笔记逐条按 updated_at 取较新者。
  /// 删除操作不做传播（防误删他端数据），记录在案为已知限制。
  /// transport 每次调用时传入，便于用户在设置里切换/配置通道。
  ///
  /// 首同步自举：对端无数据（download 返回 null）时也上传本地全量——
  /// 否则两台新设备互相等对方先推，同步永远无法启动。
  Future<SyncReport> sync(String deviceId, SyncTransport transport) async {
    final SyncPayload? remote = await transport.download();

    int pulledProgress = 0;
    int pulledBookmarks = 0;
    int pulledNotes = 0;

    if (remote != null) {
      for (ReadingProgress remoteProgress in remote.progressList) {
        final ReadingProgress? local = await _progressDao.findByBook(remoteProgress.bookId);
        if (local == null || remoteProgress.updatedAt > local.updatedAt) {
          await _progressDao.upsert(remoteProgress);
          pulledProgress++;
        }
      }
      // 一次性取出本地书签，合并与上传都基于这份快照
      final Map<String, Bookmark> localBookmarks = <String, Bookmark>{
        for (Bookmark bookmark in await _bookmarkDao.findAll()) bookmark.id: bookmark,
      };
      for (Bookmark remoteBookmark in remote.bookmarks) {
        final Bookmark? local = localBookmarks[remoteBookmark.id];
        if (local == null || remoteBookmark.updatedAt > local.updatedAt) {
          await _bookmarkDao.insert(remoteBookmark);
          localBookmarks[remoteBookmark.id] = remoteBookmark;
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
    }

    final SyncPayload local = SyncPayload(
      deviceId: deviceId,
      progressList: await _progressDao.findAll(),
      bookmarks: await _bookmarkDao.findAll(),
      notes: await _noteDao.findAll(),
    );
    await transport.upload(local);
    return SyncReport(
      pulledProgress: pulledProgress,
      pulledBookmarks: pulledBookmarks,
      pulledNotes: pulledNotes,
    );
  }
}
