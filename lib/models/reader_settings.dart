import 'dart:convert';

import 'package:flutter/material.dart';

/// 翻页动画方式。
enum PageAnimation { slide, fade, scroll }

/// 阅读外观配置：夜间模式、字体、字号、行距、页边距、翻页动画。
class ReaderSettings {
  const ReaderSettings({
    required this.themeMode,
    required this.paletteIndex,
    required this.fontFamily,
    required this.fontScale,
    required this.lineHeight,
    required this.marginIndex,
    required this.pageAnimation,
  });

  factory ReaderSettings.defaults() {
    return const ReaderSettings(
      themeMode: ThemeMode.system,
      paletteIndex: 0,
      fontFamily: 'system',
      fontScale: 1.0,
      lineHeight: 1.8,
      marginIndex: 1,
      pageAnimation: PageAnimation.slide,
    );
  }

  final ThemeMode themeMode; // system / light / dark（夜间模式开关）
  final int paletteIndex; // 配色方案下标
  final String fontFamily; // system / serif / kai
  final double fontScale; // 字号倍数 0.8 ~ 1.6
  final double lineHeight; // 行距倍数 1.4 ~ 2.4
  final int marginIndex; // 页边距档位 0/1/2
  final PageAnimation pageAnimation;

  /// 页边距档位对应的水平/垂直边距（逻辑像素，按 6.1 英寸屏设计）。
  static const List<List<double>> marginPresets = <List<double>>[
    <double>[16, 12],
    <double>[24, 20],
    <double>[32, 28],
  ];

  /// 可选配色数量。必须与 `ReadingPalette.all.length` 一致，
  /// 由测试 (`reader_settings_test.dart`) 断言，避免两边漂移。
  static const int paletteCount = 5;

  /// 允许的字体族。
  static const Set<String> fontFamilies = <String>{'system', 'serif', 'kai'};

  /// 数值范围。落在这个区间外的值不是「用户偏好」，是脏数据。
  static const double minFontScale = 0.8;
  static const double maxFontScale = 1.6;
  static const double minLineHeight = 1.4;
  static const double maxLineHeight = 2.4;

  double get horizontalMargin => marginPresets[_safeMarginIndex][0];

  double get verticalMargin => marginPresets[_safeMarginIndex][1];

  /// 即使有人绕过 [decode] 直接构造出越界的 marginIndex，
  /// 取值也不会 RangeError —— 阅读器崩溃比钳位难看多了。
  int get _safeMarginIndex => marginIndex.clamp(0, marginPresets.length - 1);

  ReaderSettings copyWith({
    ThemeMode? themeMode,
    int? paletteIndex,
    String? fontFamily,
    double? fontScale,
    double? lineHeight,
    int? marginIndex,
    PageAnimation? pageAnimation,
  }) {
    return ReaderSettings(
      themeMode: themeMode ?? this.themeMode,
      paletteIndex: paletteIndex ?? this.paletteIndex,
      fontFamily: fontFamily ?? this.fontFamily,
      fontScale: fontScale ?? this.fontScale,
      lineHeight: lineHeight ?? this.lineHeight,
      marginIndex: marginIndex ?? this.marginIndex,
      pageAnimation: pageAnimation ?? this.pageAnimation,
    );
  }

  String encode() {
    return jsonEncode(<String, Object?>{
      'theme_mode': themeMode.name,
      'palette_index': paletteIndex,
      'font_family': fontFamily,
      'font_scale': fontScale,
      'line_height': lineHeight,
      'margin_index': marginIndex,
      'page_animation': pageAnimation.name,
    });
  }

  /// 从 settings 表的 JSON 解码。
  ///
  /// **永不抛异常**。旧版本写入的字段、被截断的 JSON、越界的下标，
  /// 都不该让应用启动即崩：这里统一退化成默认值 + 钳到合法区间。
  /// 之前 `margin_index: 7` 会 RangeError、缺字段会 Null cast 失败、
  /// 非 JSON 会 FormatException——三种都会在启动路径上炸掉。
  static ReaderSettings decode(String raw) {
    final ReaderSettings defaults = ReaderSettings.defaults();
    if (raw.trim().isEmpty) {
      return defaults;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return defaults;
    }
    if (decoded is! Map) {
      return defaults;
    }
    final Map<String, Object?> json = decoded.cast<String, Object?>();

    return ReaderSettings(
      themeMode: _enumByName(ThemeMode.values, json['theme_mode'], defaults.themeMode),
      paletteIndex:
          _clampInt(json['palette_index'], 0, paletteCount - 1, defaults.paletteIndex),
      fontFamily: _fontFamily(json['font_family'], defaults.fontFamily),
      fontScale:
          _clampDouble(json['font_scale'], minFontScale, maxFontScale, defaults.fontScale),
      lineHeight: _clampDouble(
          json['line_height'], minLineHeight, maxLineHeight, defaults.lineHeight),
      marginIndex:
          _clampInt(json['margin_index'], 0, marginPresets.length - 1, defaults.marginIndex),
      pageAnimation:
          _enumByName(PageAnimation.values, json['page_animation'], defaults.pageAnimation),
    );
  }

  static T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
    for (final T value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    return fallback;
  }

  static int _clampInt(Object? raw, int min, int max, int fallback) {
    if (raw is! num) {
      return fallback;
    }
    return raw.toInt().clamp(min, max);
  }

  static double _clampDouble(Object? raw, double min, double max, double fallback) {
    if (raw is! num) {
      return fallback;
    }
    final double value = raw.toDouble();
    if (value.isNaN || value.isInfinite) {
      return fallback;
    }
    return value.clamp(min, max);
  }

  static String _fontFamily(Object? raw, String fallback) {
    if (raw is String && fontFamilies.contains(raw)) {
      return raw;
    }
    return fallback;
  }
}
