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

  /// 娃娃自查错题本（GET /tasks/wrong-questions，不含答案）。
  Future<List<WrongQuestionModel>> childWrongQuestions();

  /// 家长查看某娃娃的错题本（GET /tasks/children/{id}/wrong-questions，含答案）。
  Future<List<WrongQuestionModel>> parentWrongQuestions(String childId);
}
