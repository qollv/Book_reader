import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/models/reader_settings.dart';

// TC-12：DEF-11 设置 JSON 校验。脏数据曾让应用启动即崩（load 在 runApp 前且无兜底）。
void main() {
  test('越界值被 clamp 而非崩溃', () {
    final ReaderSettings settings = ReaderSettings.decode(
      '{"theme_mode":"dark","palette_index":9,"font_family":"system",'
      '"font_scale":6.0,"line_height":0.2,"margin_index":7,"page_animation":"slide"}',
    );
    expect(settings.paletteIndex, lessThan(5));
    expect(settings.fontScale, lessThanOrEqualTo(1.6));
    expect(settings.lineHeight, greaterThanOrEqualTo(1.4));
    // 越界下标访问不再抛 RangeError
    expect(settings.horizontalMargin, greaterThan(0));
    expect(settings.verticalMargin, greaterThan(0));
  });

  test('缺字段 / 非 JSON / 空串均回落默认值', () {
    for (final String raw in <String>[
      '{"theme_mode":"dark"}',
      'not a json at all',
      '',
      '[1,2,3]',
    ]) {
      final ReaderSettings settings = ReaderSettings.decode(raw);
      expect(settings.fontScale, 1.0);
      expect(settings.marginIndex, 1);
    }
  });

  test('encode → decode 往返等值', () {
    const ReaderSettings original = ReaderSettings(
      themeMode: ThemeMode.dark,
      paletteIndex: 2,
      fontFamily: 'serif',
      fontScale: 1.3,
      lineHeight: 2.0,
      marginIndex: 2,
      pageAnimation: PageAnimation.scroll,
    );
    final ReaderSettings decoded = ReaderSettings.decode(original.encode());
    expect(decoded.themeMode, ThemeMode.dark);
    expect(decoded.paletteIndex, 2);
    expect(decoded.fontScale, 1.3);
    expect(decoded.pageAnimation, PageAnimation.scroll);
  });
}
