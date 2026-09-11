import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../domain/assistant_event.dart';

/// 悬浮助手对话请求体（ADR-0024）：只需自由文本 + 角色（由后端 JWT 解析）。
/// 学科 / 意图由后端 AgentRuntime 自动识别，前端无需预填。
class AssistantChatReq {
  final String message;
  final String? sessionId;
  final String? model;
  final List<Map<String, dynamic>>? history;
  final List<String>? focusInterest;

  const AssistantChatReq({
    required this.message,
    this.sessionId,
    this.model,
    this.history,
    this.focusInterest,
  });

  Map<String, dynamic> toJson() => {
        'message': message,
        if (sessionId != null) 'session_id': sessionId,
        if (model != null) 'model': model,
        if (history != null) 'history': history,
        if (focusInterest != null) 'focus_interest': focusInterest,
      };
}

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

/// 结构化出题请求体（ADR-0034 P1）：直接收 specs，服务端据此构造 prompt，
/// 经 `/tasks/generate` 流式返回题卡，不再拼自然语言走 `/assistant/chat`。
class TaskGenerateReq {
  final List<TaskSpecModel> specs;
  final String? model;
  final List<String>? focusInterest;
  final String? childId;

  const TaskGenerateReq({
    required this.specs,
    this.model,
    this.focusInterest,
    this.childId,
  });

  Map<String, dynamic> toJson() => {
        'specs': specs.map((s) => s.toJson()).toList(),
        if (model != null) 'model': model,
        if (focusInterest != null) 'focus_interest': focusInterest,
        if (childId != null) 'child_id': childId,
      };
}

/// 结构化出题客户端：封装 `POST /tasks/generate` 的 SSE 流，逐帧解析为 [AssistantEvent]。
///
/// 与 [AssistantApiClient.streamChat] 共用同一套 SSE 分帧解析；事件协议完全一致
/// （TOOL_CALL / STEP / THINKING / DATA / ASSISTANT_MESSAGE / DONE），前端 fold 无需改动。
extension TaskGenerateClient on AssistantApiClient {
  Stream<AssistantEvent> streamGenerate(TaskGenerateReq req) =>
      _streamSse('/tasks/generate', req.toJson());
}
