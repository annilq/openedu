/// 课堂练习内容块（courseware-round-3 T06：去 kind 后的第四可选内容块）。
///
/// 与 [CoursewareSectionModel.materials] / [scene] 并列，任何环节都能挂。旧 AI 起草
/// 数据走 [CoursewareSectionModel.practice] 的回退读取（[CoursewareSectionModel] 里
/// 优先顶层 `practice`，否则回退旧 `payload['qtype']`）。
///
/// [qtype] 对齐后端题型域 `{choice, fill, calc, open}`（见 ADR-0004 D5）。
class CoursewarePracticeBlock {
  const CoursewarePracticeBlock({
    this.qtype = 'choice',
    this.count = 3,
    this.hints = '',
  });

  /// 题型：choice / fill / calc / open。默认 choice。
  final String qtype;

  /// 题量。默认 3。
  final int count;

  /// 提示级别 / 说明文案（旧字段叫 hint_level，统一为自由文本 hints）。
  final String hints;

  factory CoursewarePracticeBlock.fromJson(Map<String, dynamic> json) {
    final rawCount = json['count'];
    final count = rawCount is int
        ? rawCount
        : int.tryParse(rawCount?.toString() ?? '') ?? 3;
    return CoursewarePracticeBlock(
      qtype: _coerceString(json['qtype'], 'choice'),
      count: count,
      hints: _coerceHints(json['hints']),
    );
  }

  /// 把任意来源值收敛成非空字符串：旧 AI 起草数据把 [hints] 存成字符串数组，
  /// 新数据（[toJson]）是单串；两者都要能解析，否则 `as String?` 在 List 上抛
  /// 「type List is not subtype of string」，单条脏数据会拖垮整份课件列表解析。
  static String _coerceHints(dynamic raw) {
    if (raw is String) return raw;
    if (raw is List) {
      return raw
          .where((e) => e != null)
          .map((e) => e.toString())
          .join('\n');
    }
    return '';
  }

  /// [qtype] 同理收敛：容错非字符串来源，缺省回落 choice。
  static String _coerceString(dynamic raw, String fallback) {
    if (raw is String) return raw;
    if (raw != null) return raw.toString();
    return fallback;
  }

  Map<String, dynamic> toJson() => {
        'qtype': qtype,
        'count': count,
        'hints': hints,
      };

  CoursewarePracticeBlock copyWith({
    String? qtype,
    int? count,
    String? hints,
  }) =>
      CoursewarePracticeBlock(
        qtype: qtype ?? this.qtype,
        count: count ?? this.count,
        hints: hints ?? this.hints,
      );
}
