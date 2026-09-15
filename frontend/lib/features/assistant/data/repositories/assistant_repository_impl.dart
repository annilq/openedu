import '../assistant_api_client.dart';
import '../../domain/assistant_event.dart';
import '../../domain/assistant_requests.dart';
import '../../domain/repositories/assistant_repository.dart';

/// AI 能力的 SSE 传输适配。
///
/// 四个方法都是一跳转发到 [AssistantApiClient]，看着像 pass-through，但这里是
/// **端口与适配器**而非「白垫一层」：上层依赖的是「给我事件流」这个领域能力，
/// 不需要知道它是 SSE、WebSocket 还是本地 mock。换传输方式时只改本文件。
class AssistantRepositoryImpl implements AssistantRepository {
  AssistantRepositoryImpl(this._client);

  final AssistantApiClient _client;

  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) => _client.streamChat(req);

  @override
  Stream<AssistantEvent> generate(TaskGenerateReq req) =>
      _client.streamGenerate(req);

  @override
  Stream<AssistantEvent> regenerateOne({
    required String taskId,
    required String tqId,
  }) =>
      _client.streamRegenerateOne(taskId: taskId, tqId: tqId);

  @override
  Stream<AssistantEvent> regenerateAll({required String taskId}) =>
      _client.streamRegenerateAll(taskId: taskId);
}
