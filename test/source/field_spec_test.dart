import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:novel_reader/core/source/field_spec.dart';

void main() {
  group('FieldSpec.parse', () {
    test('只有选择器时取文本', () {
      final FieldSpec spec = FieldSpec.parse('#info h1');
      expect(spec.selector, '#info h1');
      expect(spec.target, isNull);
      expect(spec.ops, isEmpty);
    });

    test('@attr 与多个算子被拆开', () {
      final FieldSpec spec = FieldSpec.parse('a@href|regex:/read/(\\d+)|trim');
      expect(spec.selector, 'a');
      expect(spec.target, 'href');
      expect(spec.ops.length, 2);
    });

    test('选择器可以为空，表示当前节点自身', () {
      final FieldSpec spec = FieldSpec.parse('@href|regex:(\\d+)');
      expect(spec.isSelf, isTrue);
      expect(spec.target, 'href');
    });

    test('parseMap 跳过空规格（manifest 里常见的省略写法）', () {
      final Map<String, FieldSpec> map = FieldSpec.parseMap(<String, String>{
        'title': '',
        'id': 'a@href',
      });
      expect(map.containsKey('title'), isFalse);
      expect(map.containsKey('id'), isTrue);
    });
  });

  group('FieldSpec.extract', () {
    final document = html_parser.parse('''
      <div id="info">
        <h1>星海拾遗</h1>
        <span class="author">作者：林间</span>
        <img class="cover" src="/cover/101.jpg">
        <a class="detail" href="/read/1001">第一章</a>
      </div>
      <div class="tags"><span class="tag">科幻</span><span class="tag">冒险</span></div>
    ''');
    final root = document.documentElement!;
    final Uri base = Uri.parse('https://example.com/book/101');

    test('取文本并自动 trim', () {
      expect(FieldSpec.parse('#info h1').extractFirst(root), '星海拾遗');
    });

    test('取属性', () {
      expect(FieldSpec.parse('a.detail@href').extractFirst(root), '/read/1001');
    });

    test('regex 抽第一组', () {
      expect(
        FieldSpec.parse('a.detail@href|regex:/read/(\\d+)').extractFirst(root),
        '1001',
      );
    });

    test('absUrl 解析成绝对地址', () {
      expect(
        FieldSpec.parse('img.cover@src|absUrl').extractFirst(root, base: base),
        'https://example.com/cover/101.jpg',
      );
    });

    test('replace 做字面替换', () {
      expect(
        FieldSpec.parse('.author|replace:作者：,').extractFirst(root),
        '林间',
      );
    });

    test('extractAll 取多值字段（标签）', () {
      expect(
        FieldSpec.parse('.tag').extractAll(root),
        <String>['科幻', '冒险'],
      );
    });

    test('number 从混合文本里抽数字', () {
      // 文本里没有数字 → 结果为空串 → 被丢弃 → null
      expect(FieldSpec.parse('#info h1|number').extractFirst(root), isNull);
      expect(FieldSpec.parse('a.detail@href|number').extractFirst(root), '1001');
    });

    test('replace 支持半角逗号与等号两种分隔符', () {
      expect(FieldSpec.parse('.author|replace:作者：,').extractFirst(root), '林间');
      expect(FieldSpec.parse('.author|replace:作者：=').extractFirst(root), '林间');
    });

    test('正则写错时不抛异常，返回原值（单条规则坏掉不拖垮整章）', () {
      expect(
        FieldSpec.parse('#info h1|regex:([unclosed').extractFirst(root),
        '星海拾遗',
      );
    });

    test('正则不匹配时返回空，由调用方决定回退', () {
      expect(FieldSpec.parse('#info h1|regex:(\\d+)').extractFirst(root), isNull);
    });

    test('选择器没命中返回 null', () {
      expect(FieldSpec.parse('.nothing-here').extractFirst(root), isNull);
    });
  });
}
