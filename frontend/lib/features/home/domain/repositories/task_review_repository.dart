import '../../../../shared/domain/models/models.dart';

/// 草稿任务审核：逐题增删编辑、入库、锁定、派发、作废。
///
/// 流式动作（换一题 / 整卷重生成）走
/// `assistant/domain/repositories/assistant_repository.dart`——那边才是 AI 能力。
abstract class TaskReviewRepository {
  Future<TaskModel> load(String taskId);

  /// R-Q3：单题加入题库。
  Future<QuestionModel> promoteOne({
    required String taskId,
    required String tqId,
  });

  /// 一键把所有未入库的题批量 promote。
  Future<TaskModel> promoteAll(String taskId);

  /// R-Q5=b：删除草稿项（后端级联删 Question，若已入题库）。
  Future<void> removeOne({required String taskId, required String tqId});

  /// R-Q4：编辑草稿快照题（仅 stem/options/answer/explanation 四字段）。
  Future<QuestionModel> editOne({
    required String taskId,
    required String tqId,
    required Map<String, dynamic> edits,
  });

  /// 锁定草稿成卷（R-Q1=c 自动 promote-all）。
  Future<TaskModel> confirm(String taskId);

  /// 派发给指定娃娃。
  Future<TaskModel> assign({required String taskId, required String childId});

  /// 作废草稿（R-Q5=b，级联删 Question）。
  Future<void> discard(String taskId);
}
