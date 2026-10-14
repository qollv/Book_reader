import 'package:flutter/material.dart';

import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/ui/theme/reading_palettes.dart';

/// 解析最终主题模式。
///
/// 夜间配色强制走深色主题，避免「系统日间 + 夜间底色」的违和组合；
/// 放在独立文件里供 app 与阅读页共用，避免页面反向依赖 app 装配文件。
ThemeMode resolveThemeMode(ReaderSettings settings) {
  if (settings.themeMode == ThemeMode.dark || settings.themeMode == ThemeMode.light) {
    return settings.themeMode;
  }
  final bool paletteIsDark = ReadingPalette.all[settings.paletteIndex].isDark;
  return paletteIsDark ? ThemeMode.dark : ThemeMode.system;
}
