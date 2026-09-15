import '../assistant_event.dart';
import '../assistant_requests.dart';

/// AI 能力端口：对话 / 结构化出题 / 重生成，统一以事件流形式返回。
///
/// 刻意不暴露 SSE / HTTP 概念——上层只认 [AssistantEvent] 流。
/// 实现是 `AssistantApiClient`（SSE 传输），但 presentation 层不需要知道。
abstract class AssistantRepository {
  /// 悬浮助手对话（ADR-0024 单一入口 POST /assistant/chat）。
  Stream<AssistantEvent> chat(AssistantChatReq req);

  /// 结构化出题（POST /tasks/generate，ADR-0034）。
  Stream<AssistantEvent> generate(TaskGenerateReq req);

  /// 单题重生成的流式版（草稿审核页「换一题」）。
  Stream<AssistantEvent> regenerateOne({
    required String taskId,
    required String tqId,
  });

  /// 整卷重生成的流式版（草稿审核页「整卷重生成」）。
  Stream<AssistantEvent> regenerateAll({required String taskId});
}
