import 'package:flutter/material.dart';

/// 阅读配色：背景 / 正文 / 次要文字，后两个为夜间专用深色底。
class ReadingPalette {
  const ReadingPalette({
    required this.name,
    required this.background,
    required this.text,
    required this.secondary,
    required this.isDark,
  });

  final String name;
  final Color background;
  final Color text;
  final Color secondary;
  final bool isDark;

  static const List<ReadingPalette> all = <ReadingPalette>[
    ReadingPalette(
      name: '纸白',
      background: Color(0xFFFFFFFF),
      text: Color(0xFF1A1A1A),
      secondary: Color(0xFF8A8A8A),
      isDark: false,
    ),
    ReadingPalette(
      name: '羊皮',
      background: Color(0xFFF3E5C8),
      text: Color(0xFF3B2F1E),
      secondary: Color(0xFF9C8B6E),
      isDark: false,
    ),
    ReadingPalette(
      name: '护眼',
      background: Color(0xFFC7EDCC),
      text: Color(0xFF1F3B26),
      secondary: Color(0xFF5F7F68),
      isDark: false,
    ),
    ReadingPalette(
      name: '夜间',
      background: Color(0xFF141414),
      text: Color(0xFFB5B5B5),
      secondary: Color(0xFF6A6A6A),
      isDark: true,
    ),
    ReadingPalette(
      name: '深蓝',
      background: Color(0xFF101C2E),
      text: Color(0xFFAFC4DE),
      secondary: Color(0xFF5A6E8C),
      isDark: true,
    ),
  ];
}
