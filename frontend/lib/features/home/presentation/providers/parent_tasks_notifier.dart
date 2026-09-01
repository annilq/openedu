import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../data/datasource/tasks_remote_data_source.dart';

// ── 家长任务列表状态机 ──
sealed class ParentTasksState {
  const ParentTasksState();
}

class ParentTasksIdle extends ParentTasksState {
  const ParentTasksIdle();
}

class ParentTasksLoading extends ParentTasksState {
  const ParentTasksLoading();
}

class ParentTasksLoaded extends ParentTasksState {
  final List<TaskModel> tasks; // 本家长全部任务（后端已按 created_at 倒序）
  const ParentTasksLoaded(this.tasks);
}

class ParentTasksError extends ParentTasksState {
  final String message;
  const ParentTasksError(this.message);
}

class ParentTasksNotifier extends StateNotifier<ParentTasksState> {
  final TasksRemoteDataSource _ds;
  ParentTasksNotifier(this._ds) : super(const ParentTasksIdle());

  Future<void> load() async {
    if (state is ParentTasksLoading) return;
    state = const ParentTasksLoading();
    try {
      final tasks = await _ds.getTasks();
      state = ParentTasksLoaded(tasks);
    } catch (e) {
      state = ParentTasksError(e.toString());
    }
  }
}

final parentTasksNotifierProvider =
    StateNotifierProvider<ParentTasksNotifier, ParentTasksState>((ref) {
  final ds = TasksRemoteDataSource(ref.watch(networkServiceProvider));
  return ParentTasksNotifier(ds);
});
