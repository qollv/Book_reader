import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/dao/settings_dao.dart';
import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/state/settings_controller.dart';

// TC-21：DEF-09 设置更新时序。update 必须先 notifyListeners 再持久化，
// 否则持久化 I/O 阻塞期间 UI 停在上旧选中态，快节奏点击会被按钮吞掉；
// 持久化失败时回滚到上一份设置并再次通知，避免内存与磁盘不一致。
void main() {
  group('SettingsController.update 时序', () {
    test('持久化完成前通知已发出、内存已更新', () async {
      final _DeferredSaveDao dao = _DeferredSaveDao();
      final SettingsController controller = SettingsController(dao);
      addTearDown(controller.dispose);

      int notifications = 0;
      controller.addListener(() => notifications++);

      final Completer<void> saveGate = Completer<void>();
      dao.saveGate = saveGate.future;
      final Future<void> pending = controller.update(
        ReaderSettings.defaults().copyWith(fontScale: 1.5),
      );

      // save 尚未完成：通知已发出、读取方已看到新值
      expect(notifications, 1);
      expect(controller.settings.fontScale, 1.5);

      saveGate.complete();
      await pending;
      expect(dao.saveCalls, 1);
    });

    test('持久化失败回滚到上一份设置并再次通知', () async {
      final _DeferredSaveDao dao = _DeferredSaveDao()
        ..saveError = Exception('disk full');
      final SettingsController controller = SettingsController(dao);
      addTearDown(controller.dispose);

      final double originalScale = controller.settings.fontScale;
      int notifications = 0;
      controller.addListener(() => notifications++);

      await expectLater(
        controller.update(ReaderSettings.defaults().copyWith(fontScale: 2.0)),
        throwsA(isA<Exception>()),
      );

      expect(controller.settings.fontScale, originalScale,
          reason: '落库失败不得让内存停留在未持久化的值上');
      expect(notifications, 2, reason: '一次变更通知 + 一次回滚通知');
    });
  });
}

/// 保存动作可被测试门控的假 DAO：挂起/抛错由字段控制。
class _DeferredSaveDao implements SettingsDao {
  Future<void>? saveGate;
  Object? saveError;
  int saveCalls = 0;

  @override
  Future<String?> load() async => null;

  @override
  Future<void> save(String payload) async {
    saveCalls++;
    if (saveError != null) {
      throw saveError!;
    }
    if (saveGate != null) {
      await saveGate;
    }
  }
}
