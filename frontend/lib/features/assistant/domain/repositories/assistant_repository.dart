import '../assistant_event.dart';
import '../assistant_requests.dart';
import '../conversation.dart';

/// 延后删除的句柄：撤销时凭 [id] 找回到期定时器。
///
/// 前端延后删除用——后端无改动，5 秒窗口内可撤销，到期才真删。
class ScheduledDeleteHandle {
  const ScheduledDeleteHandle({required this.id, required this.ids});

  /// 句柄 id，传给 [cancelScheduledDelete] 撤销。
  final String id;

  /// 本次（待）删除的会话 id，方便上层对账。
  final List<String> ids;
}

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

  /// 家长的历史会话列表（含名下娃娃的），最近活动倒序（ADR-0048）。
  Future<List<AssistantConversation>> conversations();

  /// 一次会话的回放（气泡 + 卡片），只读查看与恢复续接共用。
  Future<AssistantConversationDetail> conversationDetail(String conversationId);

  /// 批量删除本家长名下的会话及其关联消息（多选删除，ADR-0048 补充）。
  ///
  /// 后端只认 parent_id 匹配的会话（孩子的会话也归家长，一并可删），
  /// 越权的 id 静默忽略。返回实际删除的会话条数。
  Future<int> deleteConversations(List<String> ids);

  /// 延后删除：先不碰后端，[window] 内可凭句柄 [cancelScheduledDelete] 撤销；
  /// 到期才回调 [onConfirm]（通常由它去真删后端）。返回句柄供撤销用。
  ///
  /// 纯前端机制——后端无改动，给 5 秒误删兜底（critique 评估 P1）。
  ScheduledDeleteHandle scheduleDelete(
    List<String> ids, {
    required Future<void> Function() onConfirm,
    Duration window = const Duration(seconds: 5),
  });

  /// 撤销延后删除：句柄仍在窗口内（未过期）→ 取消定时器并移除、返回 true；
  /// 已过期执行（或句柄无效）→ 返回 false。
  bool cancelScheduledDelete(String handleId);
}
