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

  double get horizontalMargin => marginPresets[marginIndex][0];
  double get verticalMargin => marginPresets[marginIndex][1];

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

  static ReaderSettings decode(String raw) {
    if (raw.isEmpty) {
      return ReaderSettings.defaults();
    }
    final Map<String, Object?> json = jsonDecode(raw) as Map<String, Object?>;
    return ReaderSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == json['theme_mode'],
        orElse: () => ThemeMode.system,
      ),
      paletteIndex: json['palette_index'] as int,
      fontFamily: json['font_family'] as String,
      fontScale: (json['font_scale'] as num).toDouble(),
      lineHeight: (json['line_height'] as num).toDouble(),
      marginIndex: json['margin_index'] as int,
      pageAnimation: PageAnimation.values.firstWhere(
        (animation) => animation.name == json['page_animation'],
        orElse: () => PageAnimation.slide,
      ),
    );
  }
}
