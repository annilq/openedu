import 'package:flutter/widgets.dart';

import '../../../../../shared/domain/models/models.dart';
import 'parent_task_spec_row.dart';

/// 一行学科规格的**数据**（年级 / 学期 / 学科 / 知识点 / 题型 / 题数）。
///
/// 从 `parent_task_form_view` 拆出的理由（ADR-0058 文件规模）：本类持有两个
/// [TextEditingController]，是表单里唯一「有状态」的部分，与纯展示的
/// [TaskSpecRowEditor] 恰好是数据/视图的一对。拆开后表单只留出口与状态编排，
/// 「行的生命周期归谁管」这件事也只在这一处能读到。
///
/// 生命周期必须跟表单一致（[dispose] 由表单调用）——控制器提前释放会在表单
/// 卸载后被 TextField 二次访问而抛 use-after-dispose。
class TaskSpecRow {
  String subject;
  final TextEditingController knowledgePoint;
  final TextEditingController count;

  /// 默认题型 = 学科白名单首项（ADR-0055 §12）：数学 calc / 语文 fill / 英语 choice。
  String qtype = defaultQtypeFor('数学');

  // null = 继承当前选中娃娃的年级；非 null = 家长手动覆盖。
  int? grade;

  /// 学期（ADR-0061 发布任务对接资料库）：'' = 不限/整学年。选定后知识点目录按该
  /// 学期联动，出题时随规格下发到每道题，讲解时命中同学期的交互场景模板。
  String semester = '';

  TaskSpecRow({
    String? subject,
    String? knowledgePoint,
    String? count,
    String? semester,
  }) : subject = subject ?? '数学',
       semester = semester ?? '',
       knowledgePoint = TextEditingController(text: knowledgePoint ?? '两位数加减法'),
       count = TextEditingController(text: count ?? '4') {
    qtype = defaultQtypeFor(this.subject);
  }

  /// 切学科时题型随白名单联动：当前题型不在新学科白名单里就落回默认
  /// （语文/英语没有计算题，不能把上一行的 calc 留下来）。
  void onSubjectChanged(String next) {
    subject = next;
    if (!qtypesForSubject(next).contains(qtype)) {
      qtype = defaultQtypeFor(next);
    }
  }

  void dispose() {
    knowledgePoint.dispose();
    count.dispose();
  }

  /// 本行 → 出题规格；[defaultGrade] 是「未手动指定年级」时的兜底（娃娃年级）。
  TaskSpecModel toSpec(int defaultGrade) => TaskSpecModel(
    subject: subject,
    grade: grade ?? defaultGrade,
    knowledgePoint: knowledgePoint.text,
    qtype: qtype,
    count: int.tryParse(count.text) ?? 1,
    semester: semester,
  );
}
