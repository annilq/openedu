import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../review/presentation/providers/review_notifier.dart';
import '../../../tutor/presentation/providers/tutor_notifier.dart';
import 'home_notifier.dart';

/// 当前选中的娃娃（家长端全局上下文）。
/// 由侧栏顶部选择器写入，各右栏视图据此取数据。
class SelectedChild {
  final String id;
  final int grade;
  const SelectedChild({required this.id, required this.grade});
}

/// 全局选中娃娃控制器。选中即触发进度/掌握/错题/AI 记录/额度加载。
class SelectedChildNotifier extends StateNotifier<SelectedChild?> {
  SelectedChildNotifier(this._ref) : super(null);
  final Ref _ref;

  void select(String id, int grade) {
    if (state?.id == id) return;
    state = SelectedChild(id: id, grade: grade);
    _ref.read(progressNotifierProvider.notifier).load(id);
    _ref.read(masteryNotifierProvider.notifier).load(id);
    _ref.read(parentWrongQuestionsProvider.notifier).load(childId: id);
    _ref.read(tutorLogsNotifierProvider.notifier).load(childId: id);
    _ref.read(tutorQuotaNotifierProvider(id).notifier).load(childId: id);
    _ref.read(tutorUsageNotifierProvider(id).notifier).load(childId: id);
  }
}

final selectedChildProvider =
    StateNotifierProvider<SelectedChildNotifier, SelectedChild?>((ref) {
  return SelectedChildNotifier(ref);
});
