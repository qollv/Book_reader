/// URL 模板：把 `{name}` 占位符替换成变量后，相对 base 解析成绝对地址。
///
/// 只有一种占位符语法 `{name}`，不做双花括号，避免两种语法混用时的歧义。
/// 未提供的变量替换为空串并记进 [unresolved]，便于测试与排查
/// （而不是悄悄拼出一个 404 的 URL）。
class UrlTemplate {
  const UrlTemplate(this.template, {this.vars = const <String, String>{}});

  final String template;

  /// 固定变量，如 `{base}`。调用时可被 [expand] 的 vars 覆盖。
  final Map<String, String> vars;

  static final RegExp _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

  /// 展开后的原始字符串（未解析为绝对地址）。
  ({String text, List<String> unresolved}) expandRaw(Map<String, String> vars) {
    final List<String> unresolved = <String>[];
    final String text = template.replaceAllMapped(_placeholder, (Match m) {
      final String name = m.group(1)!;
      final String? value = vars[name] ?? this.vars[name];
      if (value == null) {
        unresolved.add(name);
        return '';
      }
      return value;
    });
    return (text: text, unresolved: unresolved);
  }

  /// 展开并解析为绝对 URI。
  Uri expand(Map<String, String> vars, {Uri? base}) {
    final ({String text, List<String> unresolved}) raw = expandRaw(vars);
    final Uri parsed = Uri.parse(raw.text);
    if (base != null && !parsed.hasScheme) {
      return base.resolveUri(parsed);
    }
    return parsed;
  }

  /// 测试/排查用：展开结果里的未解析变量名。
  List<String> unresolvedIn(Map<String, String> vars) => expandRaw(vars).unresolved;
}
