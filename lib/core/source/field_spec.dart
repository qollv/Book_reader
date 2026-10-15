import 'package:html/dom.dart' as dom;

/// 字段提取规格。
///
/// 语法（单行字符串，写进 manifest 的 fields 里）：
///
/// ```
/// spec      := selector ('@' target)? ('|' op)*
/// target    := 属性名 | text | html | outerHtml
/// op        := trim | absUrl | number | regex:<pattern> | replace:<from>,<to>
/// ```
///
/// 说明：`replace` 的 from/to 分隔符优先用半角逗号 `,`，没有逗号时用 `=`。
/// 空值语义：提取结果为空串的条目会被丢弃，因此 [extractFirst] 返回 `null`
/// 而不是 `''`——调用方据此用 `?? fallback` 明确决定回退值。
///
/// 例子：
/// - `#info h1`                       取文本
/// - `a@href|regex:(\d+)`             取 href 再用正则抽第一组
/// - `img@src|absUrl`                 取 src 并解析成绝对地址
/// - `.tag`                           取第一个 .tag 的文本
///
/// 设计对照：上游 LightNovelReader 把每个源的解析写成 Kotlin 代码
/// （`Wenku8WebsiteDataSource` 里一片 Jsoup 调用）；声明式规则把
/// 「选择器 + 取值 + 变换」抽成数据，换来的是**不用编译、可热改、可单测**。
class FieldSpec {
  const FieldSpec({required this.selector, this.target, this.ops = const <FieldOp>[]});

  /// CSS 选择器；空串表示当前节点自身。
  final String selector;

  /// 取值目标：null 表示取文本。
  final String? target;

  final List<FieldOp> ops;

  bool get isSelf => selector.isEmpty;

  /// 取第一个匹配项。
  String? extractFirst(dom.Element root, {Uri? base}) {
    final List<String> all = extractAll(root, base: base);
    return all.isEmpty ? null : all.first;
  }

  /// 取全部匹配项的文本值（用于 tags 这类多值字段）。
  List<String> extractAll(dom.Element root, {Uri? base}) {
    final List<dom.Element> elements = isSelf
        ? <dom.Element>[root]
        : root.querySelectorAll(selector).toList(growable: false);
    final List<String> out = <String>[];
    for (final dom.Element element in elements) {
      final String? raw = _read(element);
      if (raw == null) {
        continue;
      }
      final String value = _applyOps(raw, base: base);
      if (value.isNotEmpty) {
        out.add(value);
      }
    }
    return out;
  }

  String? _read(dom.Element element) {
    switch (target) {
      case null:
      case 'text':
        return element.text;
      case 'html':
        return element.innerHtml;
      case 'outerHtml':
        return element.outerHtml;
      default:
        return element.attributes[target!];
    }
  }

  String _applyOps(String value, {Uri? base}) {
    String result = value;
    for (final FieldOp op in ops) {
      result = op.apply(result, base: base);
    }
    // 默认就 trim：HTML 里的换行缩进噪声几乎总是无意义的
    return result.trim();
  }

  /// 解析规格字符串。
  static FieldSpec parse(String spec) {
    final List<String> parts = spec.split('|');
    final String head = parts.first.trim();
    final List<FieldOp> ops = <FieldOp>[
      for (final String op in parts.skip(1))
        if (op.trim().isNotEmpty) FieldOp.parse(op.trim()),
    ];

    final int at = head.lastIndexOf('@');
    if (at < 0) {
      return FieldSpec(selector: head, ops: ops);
    }
    return FieldSpec(
      selector: head.substring(0, at).trim(),
      target: head.substring(at + 1).trim(),
      ops: ops,
    );
  }

  /// 把 manifest 的字段表批量解析，顺带校验规格不为空。
  static Map<String, FieldSpec> parseMap(Map<String, String> fields) {
    return <String, FieldSpec>{
      for (final MapEntry<String, String> e in fields.entries)
        if (e.value.trim().isNotEmpty) e.key: FieldSpec.parse(e.value),
    };
  }
}

/// 字段提取的变换算子。
class FieldOp {
  const FieldOp._(this._kind, this._arg1, this._arg2);

  final String _kind;
  final String _arg1;
  final String _arg2;

  String apply(String value, {Uri? base}) {
    switch (_kind) {
      case 'trim':
        return value.trim();
      case 'absUrl':
        if (base == null) {
          return value;
        }
        final Uri? resolved = Uri.tryParse(value.trim());
        if (resolved == null) {
          return value;
        }
        return base.resolveUri(resolved).toString();
      case 'number':
        final RegExpMatch? m = RegExp(r'\d+(?:\.\d+)?').firstMatch(value);
        return m?.group(0) ?? '';
      case 'regex':
        final RegExp re;
        try {
          re = RegExp(_arg1);
        } on FormatException {
          return value; // 单条正则写错不影响其它字段
        }
        final RegExpMatch? m = re.firstMatch(value);
        if (m == null) {
          return '';
        }
        return m.groupCount >= 1 ? (m.group(1) ?? '') : m.group(0)!;
      case 'replace':
        return value.replaceAll(_arg1, _arg2);
      default:
        return value;
    }
  }

  static FieldOp parse(String token) {
    final int colon = token.indexOf(':');
    if (colon < 0) {
      return FieldOp._(token, '', '');
    }
    final String kind = token.substring(0, colon);
    final String arg = token.substring(colon + 1);
    if (kind == 'replace') {
      // 分隔符优先用半角逗号（中文正文里用的是全角「，」，不冲突），
      // 没有逗号时退回等号——两种写法 manifest 里都能用。
      final int comma = arg.indexOf(',');
      final int equals = arg.indexOf('=');
      final int separator = comma >= 0 ? comma : equals;
      if (separator < 0) {
        return FieldOp._('replace', arg, '');
      }
      return FieldOp._('replace', arg.substring(0, separator), arg.substring(separator + 1));
    }
    return FieldOp._(kind, arg, '');
  }
}
