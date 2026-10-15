import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/models/source_manifest.dart';

Map<String, Object?> manifestJson({
  String id = 'test.src',
  List<String> capabilities = const <String>['chapter'],
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return <String, Object?>{
    'id': id,
    'name': '测试源',
    'apiVersion': 4,
    'baseUrl': 'https://ex.com',
    'charset': 'utf-8',
    'capabilities': capabilities,
    'chapter': <String, Object?>{'path': '/read/{chapterId}', 'content': '#content p'},
    ...extra,
  };
}

void main() {
  group('SourceManifest 校验', () {
    test('最小可用声明能解析', () {
      final SourceManifest manifest = SourceManifest.fromJson(manifestJson());
      expect(manifest.id, 'test.src');
      expect(manifest.charset, 'utf-8');
      expect(manifest.supports(SourceCapability.chapter), isTrue);
      expect(manifest.supports(SourceCapability.search), isFalse);
    });

    test('缺少 id / baseUrl 时报出可读错误', () {
      expect(
        () => SourceManifest.fromJson(<String, Object?>{
          'name': 'x',
          'baseUrl': 'https://ex.com',
        }),
        throwsA(isA<SourceManifestException>()
            .having((SourceManifestException e) => e.message, 'message', contains('id'))),
      );
      expect(
        () => SourceManifest.fromJson(<String, Object?>{'id': 'x'}),
        throwsA(isA<SourceManifestException>()
            .having((SourceManifestException e) => e.message, 'message', contains('baseUrl'))),
      );
    });

    test('id 含非法字符被拒', () {
      expect(
        () => SourceManifest.fromJson(manifestJson(id: 'has space')),
        throwsA(isA<SourceManifestException>()),
      );
    });

    test('声明了能力却没有对应规则 → 直接拒装', () {
      expect(
        () => SourceManifest.fromJson(manifestJson(
          capabilities: <String>['search', 'chapter'],
        )),
        throwsA(isA<SourceManifestException>()
            .having((SourceManifestException e) => e.message, 'message', contains('search'))),
      );
    });

    test('未知能力被静默忽略（向前兼容），不报错', () {
      final SourceManifest manifest = SourceManifest.fromJson(manifestJson(
        capabilities: <String>['chapter', 'future_capability'],
      ));
      expect(manifest.capabilities, <SourceCapability>{SourceCapability.chapter});
    });

    test('未知过滤器类型报错', () {
      expect(
        () => SourceFilterRule.fromJson(<String, Object?>{
          'key': 'k',
          'type': 'rainbow',
        }),
        throwsA(isA<SourceManifestException>()),
      );
    });

    test('single 过滤器缺少 choices 报错', () {
      expect(
        () => SourceFilterRule.fromJson(<String, Object?>{'key': 'k', 'type': 'single'}),
        throwsA(isA<SourceManifestException>()
            .having((SourceManifestException e) => e.message, 'message', contains('choices'))),
      );
    });
  });

  group('过滤器展开', () {
    test('single 把显示名映射成附加参数', () {
      const SourceFilterRule rule = SourceFilterRule(
        key: 'sort',
        title: '排序',
        type: SourceFilterType.single,
        choices: <String, String>{'默认': '', '热度': '&sort=hot'},
        defaultChoice: '默认',
      );
      expect(rule.expand(choice: '热度', slider: 0, toggle: false), '&sort=hot');
      expect(rule.expand(choice: '默认', slider: 0, toggle: false), '');
    });

    test('slider 生成 key=value', () {
      const SourceFilterRule rule = SourceFilterRule(
        key: 'words',
        title: '字数',
        type: SourceFilterType.slider,
        min: 0,
        max: 100,
      );
      expect(rule.expand(choice: '', slider: 42.4, toggle: false), '&words=42');
    });

    test('toggle 打开才产生参数', () {
      const SourceFilterRule rule =
          SourceFilterRule(key: 'finished', title: '完结', type: SourceFilterType.toggle);
      expect(rule.expand(choice: '', slider: 0, toggle: true), '&finished=1');
      expect(rule.expand(choice: '', slider: 0, toggle: false), '');
    });
  });

  group('ApiCompat 分组', () {
    test('同组且源版本不高于宿主 → 兼容', () {
      expect(isSourceApiSupported(4, 4), isTrue);
      expect(isSourceApiSupported(2, 3), isTrue);
      expect(isSourceApiSupported(3, 3), isTrue);
    });

    test('源版本高于宿主 → 不兼容', () {
      expect(isSourceApiSupported(3, 2), isFalse);
    });

    test('跨组一律不兼容', () {
      expect(isSourceApiSupported(1, 4), isFalse);
      expect(isSourceApiSupported(4, 2), isFalse);
      expect(isSourceApiSupported(2, 4), isFalse);
    });

    test('未知版本号不兼容', () {
      expect(isSourceApiSupported(99, 4), isFalse);
      expect(isSourceApiSupported(4, 99), isFalse);
    });

    test('分组表覆盖了宿主版本', () {
      expect(kSourceApiGroups.any((Set<int> g) => g.contains(kHostSourceApiVersion)), isTrue);
    });
  });

  group('随包示例源', () {
    test('assets/sources/sample_source.json 必须能被解析', () async {
      final File file = File('assets/sources/sample_source.json');
      expect(file.existsSync(), isTrue, reason: '示例源是文档，也是测试对象');

      final SourceManifest manifest = SourceManifest.fromJson(
        (jsonDecode(await file.readAsString()) as Map<String, Object?>),
      );

      expect(manifest.id, 'sample.demo');
      expect(manifest.supports(SourceCapability.search), isTrue);
      expect(manifest.supports(SourceCapability.explore), isTrue);
      expect(manifest.searchTypes.length, 2);
      expect(manifest.exploreRules.length, 2);
      expect(manifest.exploreRules.first.list.filters.length, 2);
      expect(manifest.chapterRule?.contentSelector, '#content p');
      expect(manifest.volumesRule?.chapterSelector, 'li a');
    });
  });
}
