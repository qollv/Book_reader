import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/models/reader_settings.dart';
import 'package:novel_reader/state/settings_controller.dart';
import 'package:novel_reader/models/reading_palette.dart';

/// 阅读设置面板：主题、配色、字体、字号、行距、页边距、翻页方式。
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ReaderSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();
    final ReaderSettings settings = controller.settings;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('阅读设置', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const _SectionTitle('显示模式'),
            SegmentedButton<ThemeMode>(
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment<ThemeMode>(value: ThemeMode.light, label: Text('日间')),
                ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text('夜间')),
              ],
              selected: <ThemeMode>{settings.themeMode},
              onSelectionChanged: (Set<ThemeMode> selection) =>
                  controller.setThemeMode(selection.first),
            ),
            const _SectionTitle('配色'),
            Wrap(
              spacing: 10,
              children: <Widget>[
                for (int i = 0; i < ReadingPalette.all.length; i++)
                  ChoiceChip(
                    label: Text(ReadingPalette.all[i].name),
                    selected: settings.paletteIndex == i,
                    backgroundColor: ReadingPalette.all[i].background,
                    labelStyle: TextStyle(color: ReadingPalette.all[i].text),
                    onSelected: (_) => controller.setPalette(i),
                  ),
              ],
            ),
            const _SectionTitle('字体'),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'system', label: Text('系统')),
                ButtonSegment<String>(value: 'serif', label: Text('衬线')),
              ],
              selected: <String>{settings.fontFamily},
              onSelectionChanged: (Set<String> selection) =>
                  controller.setFontFamily(selection.first),
            ),
            const _SectionTitle('字号'),
            _SliderRow(
              value: settings.fontScale,
              min: 0.8,
              max: 1.6,
              divisions: 8,
              label: '${(settings.fontScale * 100).round()}%',
              onChanged: controller.setFontScale,
            ),
            const _SectionTitle('行距'),
            _SliderRow(
              value: settings.lineHeight,
              min: 1.4,
              max: 2.4,
              divisions: 10,
              label: settings.lineHeight.toStringAsFixed(1),
              onChanged: controller.setLineHeight,
            ),
            const _SectionTitle('页边距'),
            SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text('窄')),
                ButtonSegment<int>(value: 1, label: Text('适中')),
                ButtonSegment<int>(value: 2, label: Text('宽')),
              ],
              selected: <int>{settings.marginIndex},
              onSelectionChanged: (Set<int> selection) => controller.setMargin(selection.first),
            ),
            const _SectionTitle('翻页方式'),
            SegmentedButton<PageAnimation>(
              segments: const <ButtonSegment<PageAnimation>>[
                ButtonSegment<PageAnimation>(value: PageAnimation.slide, label: Text('左右滑动')),
                ButtonSegment<PageAnimation>(value: PageAnimation.scroll, label: Text('上下滚动')),
                ButtonSegment<PageAnimation>(value: PageAnimation.fade, label: Text('淡入')),
              ],
              selected: <PageAnimation>{settings.pageAnimation},
              onSelectionChanged: (Set<PageAnimation> selection) =>
                  controller.setPageAnimation(selection.first),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 48, child: Text(label, textAlign: TextAlign.right)),
      ],
    );
  }
}
