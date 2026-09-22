import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 出题表单预填（ADR-0060 D1）：从掌握度看板「就这个知识点出题」跳转时携带。
///
/// 经 [taskFormPrefillProvider] 跨导航边界传递——看板 CTA 写入、出题表单 initState
/// 读取并清空，避免下次手动进入出题页时残留旧预填。
class TaskFormPrefill {
  final String knowledgePoint;
  final List<String> weakExampleIds;

  const TaskFormPrefill({
    required this.knowledgePoint,
    this.weakExampleIds = const [],
  });
}

/// 出题表单预填载体：看板 CTA 写入请求跳转，表单读取后清空。
final taskFormPrefillProvider =
    StateProvider<TaskFormPrefill?>((ref) => null);
