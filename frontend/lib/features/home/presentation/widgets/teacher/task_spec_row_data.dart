import 'package:flutter/widgets.dart';

import '../../../../../shared/domain/models/models.dart';
import 'teacher_task_spec_row.dart';

/// 一行学科规格的**数据**（年级 / 学期 / 学科 / 知识点 / 题型 / 题数）。
///
/// 从 `teacher_task_form_view` 拆出的理由（ADR-0058 文件规模）：本类持有两个
/// [TextEditingController]，是表单里唯一「有状态」的部分，与纯展示的
/// [TaskSpecRowEditor] 恰好是数据/视图的一对。拆开后表单只留出口与状态编排，
/// 「行的生命周期归谁管」这件事也只在这一处能读到。
///
/// 生命周期必须跟表单一致（[dispose] 由表单调用）——控制器提前释放会在表单
/// 卸载后被 TextField 二次访问而抛 use-after-dispose。
///
/// 初始值纪律（2026-10-14）：每个字段的初始值都必须有数据通路，没有通路的一律
/// 留空，生成前由 [specRowError] 说人话。学科来自 CTA 预填或教师选择，题型随学科
/// 白名单派生（ADR-0055 §12），年级继承派发班级，题数由教师填写或「一键均分」
/// 分配——旧硬编码常量（数学 / 两位数加减法 / calc / 4）已全部移除。
class TaskSpecRow {
  /// null = 未选择。学科是整行的根——题型白名单与知识点目录都由它决定，
  /// 故它没有默认值。
  String? subject;
  final TextEditingController knowledgePoint;
  final TextEditingController count;

  /// null = 未选择；学科选定后落该学科白名单首项（ADR-0055 §12）。
  String? qtype;

  // null = 继承派发班级的年级；非 null = 教师手动覆盖。
  int? grade;

  /// 学期（ADR-0061 发布任务对接资料库）：'' = 不限/整学年。选定后知识点目录按该
  /// 学期联动，出题时随规格下发到每道题，讲解时命中同学期的交互场景模板。
  String semester = '';

  TaskSpecRow({
    String? subject,
    String? knowledgePoint,
    String? count,
    String? semester,
    String? qtype,
  }) : subject = subject,
       semester = semester ?? '',
       knowledgePoint = TextEditingController(text: knowledgePoint ?? ''),
       count = TextEditingController(text: count ?? '') {
    this.qtype = qtype ?? (subject == null ? null : defaultQtypeFor(subject));
  }

  /// 切学科时题型随白名单联动：当前题型不在新学科白名单里就落回默认
  /// （语文/英语没有计算题，不能把上一行的 calc 留下来）；未选题型时直接派生。
  void onSubjectChanged(String next) {
    subject = next;
    if (qtype == null || !qtypesForSubject(next).contains(qtype)) {
      qtype = defaultQtypeFor(next);
    }
  }

  void dispose() {
    knowledgePoint.dispose();
    count.dispose();
  }

  /// 本行 → 出题规格；[inheritedGrade] 是「未手动指定年级」时继承的派发班级年级。
  ///
  /// 学科 / 题型 / 年级任一未定，或知识点 / 题数未填，返回 null——调用方先过
  /// [specRowError] 拿到人话提示再转规格，null 规格不会流到请求里。
  TaskSpecModel? toSpec(int? inheritedGrade) {
    final s = subject;
    final q = qtype;
    final g = grade ?? inheritedGrade;
    if (s == null || q == null || g == null) return null;
    if (knowledgePoint.text.isEmpty) return null;
    final n = int.tryParse(count.text) ?? 0;
    if (n < 1) return null;
    return TaskSpecModel(
      subject: s,
      grade: g,
      knowledgePoint: knowledgePoint.text,
      qtype: q,
      count: n,
      semester: semester,
    );
  }
}

/// 行级校验：返回首个未定项的人话提示；整行就绪返回 null。
///
/// 与 [TaskSpecRow.toSpec] 同一套「未定」判据（学科 / 知识点 / 年级 / 题数），
/// 保证「校验通过 ⇒ 规格可构造」。年级未定通常是还没选派发班级。
String? specRowError(TaskSpecRow row, {int? inheritedGrade}) {
  if (row.subject == null) return '请选择学科';
  if (row.knowledgePoint.text.isEmpty) return '请选择知识点';
  if ((row.grade ?? inheritedGrade) == null) return '请选择年级';
  if ((int.tryParse(row.count.text) ?? 0) < 1) return '每行题数至少为 1';
  return null;
}
