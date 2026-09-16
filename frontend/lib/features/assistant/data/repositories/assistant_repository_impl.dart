import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/assistant_event.dart';
import '../../domain/assistant_requests.dart';
import '../../domain/conversation.dart';
import '../../domain/repositories/assistant_repository.dart';
import '../assistant_api_client.dart';

/// AI 能力适配器。
///
/// 事件流部分一跳转发到 [AssistantApiClient]（SSE 分帧逻辑在那里），看着像
/// pass-through，但这里是**端口与适配器**而非「白垫一层」：上层依赖的是「给我事件流」
/// 这个领域能力，不需要知道它是 SSE、WebSocket 还是本地 mock。换传输方式时只改本文件。
///
/// 会话历史的两个读方法（ADR-0048）是**普通请求**——响应即结果、不是流，所以直接经
/// [NetworkService] 取数并在这里解析成领域模型（与其余 feature 的 repository 同一写法），
/// 不再往 API 客户端里塞一份非流式传输。
class AssistantRepositoryImpl implements AssistantRepository {
  AssistantRepositoryImpl(this._client, this._network);

  final AssistantApiClient _client;
  final NetworkService _network;

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

  @override
  Future<List<AssistantConversation>> conversations() async {
    final data = await _network.get('/assistant/conversations');
    return decodeList(data, AssistantConversation.fromJson);
  }

  @override
  Future<AssistantConversationDetail> conversationDetail(
    String conversationId,
  ) async {
    final data = await _network.get('/assistant/conversations/$conversationId');
    return AssistantConversationDetail.fromJson(decodeMap(data));
  }
}
