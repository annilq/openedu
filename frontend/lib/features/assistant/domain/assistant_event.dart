/// AG-UI 式统一事件信封（与后端 `app/ai/runtime/protocol.py` 对齐，ADR-0025）。
///
/// 后端 `POST /api/v1/assistant/chat` 以 SSE 逐帧推送这些事件；
/// 前端按 [eventType] 分发渲染。
class AssistantEvent {
  final String eventType;
  final String? text; // USER_MESSAGE / ASSISTANT_MESSAGE / THINKING 的增量文本
  final String? tool; // TOOL_CALL / TOOL_RESULT：工具名
  final String? label; // TOOL_CALL / STEP：可读标签
  final Map<String, dynamic>? args; // TOOL_CALL：入参
  final dynamic result; // TOOL_RESULT：出参
  final String? status; // STEP / DONE：状态
  final Map<String, dynamic>? data; // DATA：{status,type,result}
  final String? message; // ERROR：可读错误
  final String? code; // ERROR：错误码
  final String? sessionId; // DONE：会话 id
  final bool? blocked; // 安全兜底标记
  final Map<String, dynamic>? extra; // 透传扩展字段（如路由 business）

  const AssistantEvent({
    required this.eventType,
    this.text,
    this.tool,
    this.label,
    this.args,
    this.result,
    this.status,
    this.data,
    this.message,
    this.code,
    this.sessionId,
    this.blocked,
    this.extra,
  });

  factory AssistantEvent.fromJson(Map<String, dynamic> json) {
    return AssistantEvent(
      eventType: json['eventType'] as String,
      text: json['text'] as String?,
      tool: json['tool'] as String?,
      label: json['label'] as String?,
      args: json['args'] as Map<String, dynamic>?,
      result: json['result'],
      status: json['status'] as String?,
      data: json['data'] as Map<String, dynamic>?,
      message: json['message'] as String?,
      code: json['code'] as String?,
      sessionId: json['session_id'] as String?,
      blocked: json['blocked'] as bool?,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }
}

/// 事件类型常量（与后端 [AssistantEvent.eventType] 一致）。
class AssistantEventType {
  const AssistantEventType._();

  static const runStarted = 'RUN_STARTED';
  static const userMessage = 'USER_MESSAGE';
  static const thinking = 'THINKING';
  static const assistantMessage = 'ASSISTANT_MESSAGE';
  static const toolCall = 'TOOL_CALL';
  static const toolResult = 'TOOL_RESULT';
  static const step = 'STEP';
  static const data = 'DATA';
  static const error = 'ERROR';
  static const done = 'DONE';
}
