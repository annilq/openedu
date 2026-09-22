import '../../../shared/domain/models/models.dart';

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

/// 结构化出题请求体（ADR-0034 P1）：把家长选的规格原样直传后端，
/// 由服务端据此构造出题 prompt，不再在前端拼自然语言。
class TaskGenerateReq {
  final List<TaskSpecModel> specs;
  final String? model;
  final List<String>? focusInterest;
  final String? childId;
  // 反馈边（ADR-0060 D4）：掌握度看板下发的代表错题 id，服务端据此做同类题仿写。
  final List<String>? weakExampleIds;

  const TaskGenerateReq({
    required this.specs,
    this.model,
    this.focusInterest,
    this.childId,
    this.weakExampleIds,
  });

  Map<String, dynamic> toJson() => {
        'specs': specs.map((s) => s.toJson()).toList(),
        if (model != null) 'model': model,
        if (focusInterest != null) 'focus_interest': focusInterest,
        if (childId != null) 'child_id': childId,
        if (weakExampleIds != null) 'weak_example_ids': weakExampleIds,
      };
}
