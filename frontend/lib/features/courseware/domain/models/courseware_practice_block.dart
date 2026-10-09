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
      qtype: json['qtype'] as String? ?? 'choice',
      count: count,
      hints: json['hints'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'qtype': qtype,
        'count': count,
        'hints': hints,
      };
}
