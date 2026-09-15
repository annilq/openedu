import '../models.dart';

/// 家长端「AI 答疑记录」日志（F-305）。
///
/// 这是 `features/tutor` 唯一保留的职责——家长侧可观测日志，非 AI 生成端点，
/// 因此不并入 `POST /assistant/chat`（ADR-0024/0036）。
abstract class TutorLogsRepository {
  Future<List<TutorLogModel>> logs(String childId);
}
