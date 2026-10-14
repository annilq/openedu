import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 出题表单预填（ADR-0060 D1）：从掌握度看板「就这个知识点出题」跳转时携带。
///
/// 经 [taskFormPrefillProvider] 跨导航边界传递——看板 CTA 写入、出题表单 initState
/// 读取并清空，避免下次手动进入出题页时残留旧预填。
///
/// 2026-10-14：这是表单初始值**唯一**允许的外部数据通路——学科 / 知识点 / 年级
/// 全部来自 CTA 行的掌握度数据，而不是硬编码常量。字段均可选：旧调用点照常编译，
/// 缺的值落入表单生成前校验（没有通路的一律留空，见 task_form_defaults.dart）。
class TaskFormPrefill {
  final String? subject;
  final String knowledgePoint;
  final int? grade;
  final List<String> weakExampleIds;

  const TaskFormPrefill({
    this.subject,
    required this.knowledgePoint,
    this.grade,
    this.weakExampleIds = const [],
  });
}

/// 出题表单预填载体：看板 CTA 写入请求跳转，表单读取后清空。
final taskFormPrefillProvider =
    StateProvider<TaskFormPrefill?>((ref) => null);
