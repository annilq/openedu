import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../shared/data/remote/network_service.dart';
import '../domain/assistant_event.dart';
import '../domain/assistant_requests.dart';

/// 悬浮助手客户端：封装 `POST /assistant/chat` 的 SSE 流，逐帧解析为 [AssistantEvent]。
///
/// 复用 [NetworkService.streamPost]（Dio 拦截器自动注入 Authorization、错误统一转
/// [HttpException]），避免重复实现鉴权 / 错误解析。
class AssistantApiClient {
  final NetworkService _network;

  AssistantApiClient(this._network);

  /// 发起一次对话，返回 AG-UI 事件流。
  Stream<AssistantEvent> streamChat(AssistantChatReq req) =>
      _streamSse('/assistant/chat', req.toJson());

  /// 共享 SSE 分帧解析：把 [NetworkService.streamPost] 的原始字节流按 `\n\n` 切帧，
  /// 逐帧提取 `data:` 载荷并解码为 [AssistantEvent]。
  ///
  /// [streamChat] 与 [streamGenerate] 共用此实现（ADR-0034：两接口事件协议一致），
  /// 分帧逻辑单一事实源，避免逐字复制。
  Stream<AssistantEvent> _streamSse(String path, Map<String, dynamic> body) async* {
    final byteStream = _network.streamPost(path, body: body);
    String buffer = '';
    await for (final chunk in byteStream) {
      buffer += _decode(chunk);
      var idx = buffer.indexOf('\n\n');
      while (idx != -1) {
        final frame = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        final ev = _parseFrame(frame);
        if (ev != null) yield ev;
        idx = buffer.indexOf('\n\n');
      }
    }
    if (buffer.trim().isNotEmpty) {
      final ev = _parseFrame(buffer);
      if (ev != null) yield ev;
    }
  }

  String _decode(Uint8List chunk) => utf8.decode(chunk, allowMalformed: true);

  AssistantEvent? _parseFrame(String frame) {
    for (final line in frame.split('\n')) {
      final l = line.trim();
      if (l.startsWith('data:')) {
        final jsonStr = l.substring(5).trim();
        if (jsonStr.isEmpty) continue;
        try {
          final m = jsonDecode(jsonStr) as Map<String, dynamic>;
          return AssistantEvent.fromJson(m);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }
}

/// 结构化出题客户端：封装 `POST /tasks/generate` 的 SSE 流，逐帧解析为 [AssistantEvent]。
///
/// 与 [AssistantApiClient.streamChat] 共用同一套 SSE 分帧解析；事件协议完全一致
/// （TOOL_CALL / STEP / THINKING / DATA / ASSISTANT_MESSAGE / DONE），前端 fold 无需改动。
extension TaskGenerateClient on AssistantApiClient {
  Stream<AssistantEvent> streamGenerate(TaskGenerateReq req) =>
      _streamSse('/tasks/generate', req.toJson());

  /// 单题重生成的流式版（草稿审核页「换一题」）。
  ///
  /// 同步版 `POST /tasks/{id}/questions/{tq}/regenerate` 是一次同步 LLM 调用，
  /// 常常超过普通请求的 30 秒 receiveTimeout——家长点了长时间没反应。这里改走
  /// SSE：复用流式端点的长超时，并逐帧收 RUN_STARTED/STEP/DATA/ERROR，
  /// 事件协议与 `/tasks/generate` 完全一致，无需新的帧解析器。
  Stream<AssistantEvent> streamRegenerateOne({
    required String taskId,
    required String tqId,
  }) =>
      _streamSse('/tasks/$taskId/questions/$tqId/regenerate-stream', const {});
}
