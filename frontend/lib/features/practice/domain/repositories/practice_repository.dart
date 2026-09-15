import '../../../../shared/domain/models/models.dart';

/// 练习作答：提交答案 / 打卡。
///
/// 娃娃端做题主链路。批改与错题调度更新都在后端完成，这里只负责
/// 「把答案送进去、把批改结果拿回来」。
abstract class PracticeRepository {
  /// 提交一道作答，返回批改结果。
  ///
  /// 订正作答复用同一接口（后端按 `AnswerRecord` 覆盖，不新增副作用）。
  Future<AnswerResultModel> submitAnswer(
    String taskId,
    String questionId,
    String answer,
  );

  /// 任务打卡。失败返回 `false` 而不抛——打卡失败不该打断做题流程。
  Future<bool> checkin(String taskId);
}
