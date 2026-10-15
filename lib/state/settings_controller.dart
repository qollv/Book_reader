import 'package:flutter/material.dart';

import 'package:novel_reader/data/dao/settings_dao.dart';
import 'package:novel_reader/models/reader_settings.dart';

/// 阅读外观设置状态：改任一参数立即持久化并通知阅读器重排版。
class SettingsController extends ChangeNotifier {
  SettingsController(this._settingsDao);

  final SettingsDao _settingsDao;

  ReaderSettings _settings = ReaderSettings.defaults();

  ReaderSettings get settings => _settings;

  Future<void> load() async {
    final String? raw = await _settingsDao.load();
    _settings = ReaderSettings.decode(raw ?? '');
    notifyListeners();
  }

  /// 先通知再持久化：设置面板点击后外观立即生效，不等磁盘 I/O。
  /// 持久化失败时回滚到上一份设置并重新通知，避免内存与磁盘不一致。
  Future<void> update(ReaderSettings next) async {
    final ReaderSettings previous = _settings;
    _settings = next;
    notifyListeners();
    try {
      await _settingsDao.save(next.encode());
    } catch (error) {
      _settings = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) => update(_settings.copyWith(themeMode: mode));

  Future<void> setPalette(int index) => update(_settings.copyWith(paletteIndex: index));

  Future<void> setFontFamily(String family) => update(_settings.copyWith(fontFamily: family));

  Future<void> setFontScale(double scale) => update(_settings.copyWith(fontScale: scale));

  Future<void> setLineHeight(double height) => update(_settings.copyWith(lineHeight: height));

  Future<void> setMargin(int index) => update(_settings.copyWith(marginIndex: index));

  Future<void> setPageAnimation(PageAnimation animation) =>
      update(_settings.copyWith(pageAnimation: animation));
}
