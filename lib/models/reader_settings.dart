import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:novel_reader/models/reading_palette.dart';

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
  final String fontFamily; // system / serif
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

  static const double fontScaleMin = 0.8;
  static const double fontScaleMax = 1.6;
  static const double lineHeightMin = 1.4;
  static const double lineHeightMax = 2.4;

  /// 越界下标回落默认档，防止 RangeError 崩溃启动。
  double get horizontalMargin => marginPresets[_clampIndex(marginIndex)][0];
  double get verticalMargin => marginPresets[_clampIndex(marginIndex)][1];

  static int _clampIndex(int index) => index.clamp(0, marginPresets.length - 1);

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

  /// 反序列化：任何脏数据（非 JSON、缺字段、类型不符、越界）都不得抛异常，
  /// 整体或逐字段回落到默认值——启动路径依赖它，崩溃即应用起不来。
  static ReaderSettings decode(String raw) {
    if (raw.isEmpty) {
      return ReaderSettings.defaults();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return ReaderSettings.defaults();
    }
    if (decoded is! Map<String, Object?>) {
      return ReaderSettings.defaults();
    }
    final Map<String, Object?> json = decoded;
    final ReaderSettings defaults = ReaderSettings.defaults();
    return ReaderSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == json['theme_mode'],
        orElse: () => defaults.themeMode,
      ),
      paletteIndex: _intOr(json['palette_index'], defaults.paletteIndex)
          .clamp(0, ReadingPalette.all.length - 1),
      fontFamily: json['font_family'] is String ? json['font_family'] as String : defaults.fontFamily,
      fontScale: _doubleOr(json['font_scale'], defaults.fontScale)
          .clamp(fontScaleMin, fontScaleMax),
      lineHeight: _doubleOr(json['line_height'], defaults.lineHeight)
          .clamp(lineHeightMin, lineHeightMax),
      marginIndex: _intOr(json['margin_index'], defaults.marginIndex)
          .clamp(0, marginPresets.length - 1),
      pageAnimation: PageAnimation.values.firstWhere(
        (animation) => animation.name == json['page_animation'],
        orElse: () => defaults.pageAnimation,
      ),
    );
  }

  static int _intOr(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }

  static double _doubleOr(Object? value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }
}
