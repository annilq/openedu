import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/task.dart';
import '../../domain/repositories/tasks_repository.dart';
import '../../providers/home_provider.dart';

/// 教师工作台待办聚合（ticket 20）：待审核 / 待派发 / 谁没交。
///
/// 服务端一次性聚合返回，客户端只渲染，不自行统计分页（避免徽标漏数，ADR-0053 同款陷阱）。
sealed class TeacherTodoState {
  const TeacherTodoState();
}

class TeacherTodoInitial extends TeacherTodoState {
  const TeacherTodoInitial();
}

class TeacherTodoLoading extends TeacherTodoState {
  const TeacherTodoLoading();
}

class TeacherTodoLoaded extends TeacherTodoState {
  final TeacherTodoSummary summary;
  const TeacherTodoLoaded(this.summary);
}

class TeacherTodoError extends TeacherTodoState {
  final String message;
  const TeacherTodoError(this.message);
}

class TeacherTodoNotifier extends StateNotifier<TeacherTodoState> {
  final TasksRepository _tasks;
  TeacherTodoNotifier(this._tasks) : super(const TeacherTodoInitial());

  Future<void> load() async {
    state = const TeacherTodoLoading();
    try {
      final summary = await _tasks.teacherTodoSummary();
      state = TeacherTodoLoaded(summary);
    } catch (e) {
      state = TeacherTodoError(e.toString());
    }
  }
}

final teacherTodoProvider =
    StateNotifierProvider<TeacherTodoNotifier, TeacherTodoState>((ref) {
  return TeacherTodoNotifier(ref.watch(tasksRepositoryProvider));
});
