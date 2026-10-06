import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../review/presentation/providers/review_notifier.dart';
import '../../../tutor/presentation/providers/tutor_logs_notifier.dart';
import 'home_notifier.dart';

/// 当前选中的学生（教师端全局上下文）。
/// 由侧栏顶部选择器写入，各右栏视图据此取数据。
class SelectedStudent {
  final String id;
  final int grade;
  const SelectedStudent({required this.id, required this.grade});
}

/// 全局选中学生控制器。选中即触发进度/掌握/错题/AI 记录加载。
class SelectedStudentNotifier extends StateNotifier<SelectedStudent?> {
  SelectedStudentNotifier(this._ref) : super(null);
  final Ref _ref;

  void select(String id, int grade) {
    if (state?.id == id) return;
    state = SelectedStudent(id: id, grade: grade);
    _ref.read(progressNotifierProvider.notifier).load(id);
    _ref.read(masteryNotifierProvider.notifier).load(id);
    _ref.read(teacherWrongQuestionsProvider.notifier).load(id);
    _ref.read(tutorLogsNotifierProvider.notifier).load(id);
  }
}

final selectedStudentProvider =
    StateNotifierProvider<SelectedStudentNotifier, SelectedStudent?>((ref) {
  return SelectedStudentNotifier(ref);
});
