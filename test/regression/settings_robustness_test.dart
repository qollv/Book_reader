import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/ui/theme/reading_palettes.dart';

/// ReaderSettings 解码的回归测试。
///
/// 背景：`decode` 原来直接 `jsonDecode(...) as Map` + `as int`，
/// 于是 settings 表里一旦有脏数据（旧版本写入、被截断、外面改过），
/// **启动就崩**：`margin_index: 7` → RangeError、
/// 缺字段 → `type 'Null' is not a subtype of type 'int'`、
/// 非 JSON → FormatException。设置是启动路径上的数据，
/// 它必须永不抛异常。
void main() {
  group('decode 永不抛异常', () {
    test('非 JSON 文本 → 默认值', () {
      expect(ReaderSettings.decode('not json'), ReaderSettings.defaults());
      expect(ReaderSettings.decode('{"a":'), ReaderSettings.defaults());
    });

    test('空串与纯空白 → 默认值', () {
      expect(ReaderSettings.decode(''), ReaderSettings.defaults());
      expect(ReaderSettings.decode('   '), ReaderSettings.defaults());
    });

    test('合法 JSON 但不是对象 → 默认值', () {
      expect(ReaderSettings.decode('[1,2,3]'), ReaderSettings.defaults());
      expect(ReaderSettings.decode('42'), ReaderSettings.defaults());
      expect(ReaderSettings.decode('"text"'), ReaderSettings.defaults());
    });

    test('缺字段 → 逐项取默认值（原来会 Null cast 失败）', () {
      final ReaderSettings settings = ReaderSettings.decode('{"font_scale":1.2}');
      expect(settings.fontScale, 1.2);
      expect(settings.paletteIndex, ReaderSettings.defaults().paletteIndex);
      expect(settings.marginIndex, ReaderSettings.defaults().marginIndex);
      expect(settings.lineHeight, ReaderSettings.defaults().lineHeight);
    });

    test('空对象 → 默认值', () {
      final ReaderSettings settings = ReaderSettings.decode('{}');
      expect(settings.paletteIndex, ReaderSettings.defaults().paletteIndex);
      expect(settings.fontFamily, ReaderSettings.defaults().fontFamily);
    });

    test('字段类型不符 → 该字段取默认值', () {
      final ReaderSettings settings = ReaderSettings.decode(jsonEncode(<String, Object?>{
        'palette_index': 'three',
        'font_scale': <int>[1],
        'line_height': null,
        'theme_mode': 7,
      }));
      final ReaderSettings defaults = ReaderSettings.defaults();
      expect(settings.paletteIndex, defaults.paletteIndex);
      expect(settings.fontScale, defaults.fontScale);
      expect(settings.lineHeight, defaults.lineHeight);
      expect(settings.themeMode, defaults.themeMode);
    });
  });

  group('越界值被钳位而不是崩', () {
    test('margin_index 越界后取值不抛 RangeError', () {
      final ReaderSettings settings = ReaderSettings.decode(jsonEncode(<String, Object?>{
        'margin_index': 7,
      }));
      expect(settings.marginIndex, ReaderSettings.marginPresets.length - 1);
      // 关键：这两个 getter 原来会 RangeError
      expect(settings.horizontalMargin, isNotNull);
      expect(settings.verticalMargin, isNotNull);
    });

    test('margin_index 为负数也安全', () {
      final ReaderSettings settings =
          ReaderSettings.decode(jsonEncode(<String, Object?>{'margin_index': -5}));
      expect(settings.marginIndex, 0);
      expect(settings.horizontalMargin, ReaderSettings.marginPresets[0][0]);
    });

    test('palette_index 越界被钳到配色数量内', () {
      expect(
        ReaderSettings.decode(jsonEncode(<String, Object?>{'palette_index': 99})).paletteIndex,
        ReaderSettings.paletteCount - 1,
      );
      expect(
        ReaderSettings.decode(jsonEncode(<String, Object?>{'palette_index': -1})).paletteIndex,
        0,
      );
    });

    test('font_scale / line_height 越界被钳到设计区间', () {
      final ReaderSettings big = ReaderSettings.decode(jsonEncode(<String, Object?>{
        'font_scale': 6.0,
        'line_height': 9.0,
      }));
      expect(big.fontScale, ReaderSettings.maxFontScale);
      expect(big.lineHeight, ReaderSettings.maxLineHeight);

      final ReaderSettings small = ReaderSettings.decode(jsonEncode(<String, Object?>{
        'font_scale': 0.1,
        'line_height': 0.2,
      }));
      expect(small.fontScale, ReaderSettings.minFontScale);
      expect(small.lineHeight, ReaderSettings.minLineHeight);
    });

    test('未知字体族退回默认', () {
      expect(
        ReaderSettings.decode(jsonEncode(<String, Object?>{'font_family': 'comic'})).fontFamily,
        ReaderSettings.defaults().fontFamily,
      );
      expect(
        ReaderSettings.decode(jsonEncode(<String, Object?>{'font_family': 'kai'})).fontFamily,
        'kai',
      );
    });

    test('未知枚举名退回默认', () {
      expect(
        ReaderSettings.decode(jsonEncode(<String, Object?>{'theme_mode': 'rainbow'})).themeMode,
        ReaderSettings.defaults().themeMode,
      );
      expect(
        ReaderSettings.decode(jsonEncode(<String, Object?>{'page_animation': 'zoom'})).pageAnimation,
        ReaderSettings.defaults().pageAnimation,
      );
    });

    test('直接构造出越界 marginIndex 时 getter 依然安全', () {
      const ReaderSettings bad = ReaderSettings(
        themeMode: ThemeMode.system,
        paletteIndex: 0,
        fontFamily: 'system',
        fontScale: 1,
        lineHeight: 1.8,
        marginIndex: 42,
        pageAnimation: PageAnimation.slide,
      );
      expect(bad.horizontalMargin, isNotNull);
    });
  });

  group('约定一致性', () {
    test('paletteCount 与真实配色数量一致（防止两边漂移）', () {
      expect(ReaderSettings.paletteCount, ReadingPalette.all.length);
    });

    test('encode → decode 往返保持全部字段', () {
      const ReaderSettings original = ReaderSettings(
        themeMode: ThemeMode.dark,
        paletteIndex: 3,
        fontFamily: 'serif',
        fontScale: 1.3,
        lineHeight: 2.0,
        marginIndex: 2,
        pageAnimation: PageAnimation.scroll,
      );
      final ReaderSettings restored = ReaderSettings.decode(original.encode());

      expect(restored.themeMode, original.themeMode);
      expect(restored.paletteIndex, original.paletteIndex);
      expect(restored.fontFamily, original.fontFamily);
      expect(restored.fontScale, original.fontScale);
      expect(restored.lineHeight, original.lineHeight);
      expect(restored.marginIndex, original.marginIndex);
      expect(restored.pageAnimation, original.pageAnimation);
    });
  });
}
