import '../../../../shared/domain/models/models.dart';

/// 复习与错题本：待复习队列、复习作答、错题查阅。
///
/// 与 [PracticeRepository] 的分工：练习＝首次作答（`POST /tasks/{id}/answer`），
/// 复习＝间隔重复下的二次作答（`POST /review/answer`，后端负责推进遗忘曲线）。
abstract class ReviewRepository {
  /// 娃娃端待复习队列（GET /review/due）。
  Future<List<ReviewItemModel>> dueReview();

  /// 提交一道复习作答，返回批改结果（错题调度更新在后端完成）。
  Future<AnswerResultModel> answer(String wrongQuestionId, String studentAnswer);

  /// 娃娃自查错题本（GET /tasks/wrong-questions，不含答案，游标分页 ADR-0053）。
  Future<CursorPage<WrongQuestionModel>> childWrongQuestions({
    String? cursor,
    int pageSize = 20,
  });

  /// 家长查看某娃娃的错题本（GET /tasks/children/{id}/wrong-questions，
  /// 含答案，游标分页 ADR-0053）。
  ///
  /// [scope]（ADR-0053 P2）：`active`（默认，未毕业）/ `graduated`（「已掌握」分区）。
  Future<WrongQuestionPage> parentWrongQuestions(
    String childId, {
    String? cursor,
    int pageSize = 20,
    String scope = 'active',
  });

  /// 把一条「已掌握」的错题重新加入复习（ADR-0053 P2）。
  ///
  /// 清毕业时间戳、阶段归 0、立刻到期；后端保留 wrong_count 与首次答错时间。
  Future<WrongQuestionModel> rejoinWrongQuestion(
    String childId,
    String wrongQuestionId,
  );
}
