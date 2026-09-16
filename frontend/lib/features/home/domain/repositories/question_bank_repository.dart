import '../../../../shared/domain/models/models.dart';

/// 题库：浏览 + 从题库组卷（选项 A 新建 / 选项 B 追加到草稿）。
abstract class QuestionBankRepository {
  /// 题库浏览（游标分页，ADR-0053）。
  ///
  /// [cursor] 为 null 时取第一页；非 null 时必须**原样回传**上一页响应里的
  /// `next_cursor`，不得自行构造或解析。
  Future<BankListResp> getQuestions({
    String? subject,
    int? grade,
    String? knowledgePoint,
    String? qtype,
    String? keyword,
    String? cursor,
    int pageSize = 20,
  });

  Future<TaskModel> createTaskFromBank({
    required String title,
    required String childId,
    required List<String> questionIds,
  });

  Future<TaskModel> addToTaskFromBank({
    required String taskId,
    required List<String> questionIds,
  });

  /// 选项 B 草稿选择器：家长草稿列表（GET /tasks?status=draft）。
  Future<List<TaskModel>> getDraftTasks();

  /// 批量删除题库题：被任务引用的题后端已跳过（返回分组结果）。
  Future<DeleteQuestionsResult> deleteQuestions(List<String> ids);

  /// 反查某题库题被哪些任务引用，闭环「用过 N 次 → 在哪里用」。
  Future<List<QuestionUsageItem>> getQuestionUsages(String questionId);

  /// 按 id 拉取完整任务，供引用列表跳转复核页。
  Future<TaskModel> getTaskById(String taskId);
}
