import '../../../shared/domain/models/models.dart';

/// 悬浮助手对话请求体（ADR-0024）：只需自由文本 + 角色（由后端 JWT 解析）。
/// 学科 / 意图由后端 AgentRuntime 自动识别，前端无需预填。
class AssistantChatReq {
  final String message;
  final String? sessionId;
  final String? model;
  final List<Map<String, dynamic>>? history;
  final AssistantCoursewareContext? courseware;
  final String? knowledgePointId;
  // ADR-0081：结构化动作键（如 task_generate）。非空时后端走动作直配，不再让
  // 决策模型 / LLM 分类器猜业务。会话内点 chip 切换意图靠它。
  final String? action;

  const AssistantChatReq({
    required this.message,
    this.sessionId,
    this.model,
    this.history,
    this.courseware,
    this.knowledgePointId,
    this.action,
  });

  Map<String, dynamic> toJson() => {
    'message': message,
    if (sessionId != null) 'session_id': sessionId,
    if (model != null) 'model': model,
    if (history != null) 'history': history,
    if (courseware != null) 'courseware': courseware!.toJson(),
    if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
    if (action != null) 'action': action,
  };
}

/// 结构化出题请求体（ADR-0034 P1）：把教师选的规格原样直传后端，
/// 由服务端据此构造出题 prompt，不再在前端拼自然语言。
class TaskGenerateReq {
  final List<TaskSpecModel> specs;
  final String? model;
  final String? studentId;
  // 反馈边（ADR-0060 D4）：掌握度看板下发的代表错题 id，服务端据此做同类题仿写。
  final List<String>? weakExampleIds;

  const TaskGenerateReq({
    required this.specs,
    this.model,
    this.studentId,
    this.weakExampleIds,
  });

  Map<String, dynamic> toJson() => {
    'specs': specs.map((s) => s.toJson()).toList(),
    if (model != null) 'model': model,
    if (studentId != null) 'student_id': studentId,
    if (weakExampleIds != null) 'weak_example_ids': weakExampleIds,
  };
}
