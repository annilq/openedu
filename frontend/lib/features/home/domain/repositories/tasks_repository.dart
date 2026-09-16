import '../../../../shared/domain/models/models.dart';

/// 任务读取与落库。
///
/// 只覆盖「取一次」的读资源 + 生成结果的落库；带流式进度的是
/// `assistant/domain/repositories/assistant_repository.dart`。
abstract class TasksRepository {
  /// 娃娃端今日任务（GET /tasks/today）。
  Future<List<TaskModel>> todayTasks();

  /// 家长全部任务（GET /tasks，游标分页，ADR-0053）。
  ///
  /// 返回的是 [TaskPage]：除条目外还带三个 Tab 的状态计数（否则徽标只能统计已加载页）。
  /// [cursor] 为 null 时取第一页，否则**原样回传**上一页的 `next_cursor`。
  Future<TaskPage> parentTasks({
    String? status,
    String? cursor,
    int pageSize = 20,
  });

  /// 某娃娃的进度概览。
  Future<ProgressModel> progress(String childId);

  /// 某娃娃的知识点掌握度看板。
  Future<MasteryModel> mastery(String childId);

  /// 把已生成的题卡落库为草稿任务（POST /tasks/from-generated）。
  Future<TaskModel> persistGenerated(Map<String, dynamic> body);
}
