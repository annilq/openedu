/// 运行轨迹（ADR-0088）：一次 AI 运行 + 其全部步骤——**审计 / 排障口径**的投影。
///
/// 与历史会话（`conversation.dart` 的 `AssistantConversation`/`AssistantBubble`，
/// 使用者视角的气泡投影）是**同一张后端 `Conversation`/`Message` 表上并列的两个
/// 消费者**：气泡把 `routing`/`tool_*` 这些内部步骤剥掉、只留问答；轨迹页恰恰要把
/// 它们连元数据一起渲染出来。
///
/// 因此本文件刻意**不 import conversation.dart**：两套口径各自独立，不许派生
/// 「第三套步骤→气泡」逻辑（ADR-0088 §2.3）。
library;

/// 一次 AI 运行的概要（列表行）。
///
/// 对应后端 `ai/schemas.ConversationResp`。范围（教师自家 / admin 全部）由服务端
/// 按角色钉死，前端不带 `teacher_id` 之类的过滤参数。
class RunTraceRun {
  final String id;

  /// 运行类型（`query` / `question` / `grade` / `agent`…），只作标签。
  final String kind;

  /// 运行名：后端取首条用户消息截断。
  final String title;

  /// 所用模型引用（01 落库后非空；早期运行为 null → 展示占位）。
  final String? model;

  /// `running` / `done` / `error` / `blocked`。
  final String status;

  /// 创建时间（ISO 串，展示时再格式化——与仓库既有列表页同一口径）。
  final String? createdAt;

  const RunTraceRun({
    required this.id,
    this.kind = '',
    this.title = '',
    this.model,
    this.status = '',
    this.createdAt,
  });

  factory RunTraceRun.fromJson(Map<String, dynamic> json) => RunTraceRun(
        id: '${json['id']}',
        kind: '${json['kind'] ?? ''}',
        title: (json['title'] as String?)?.trim() ?? '',
        model: json['model'] as String?,
        status: '${json['status'] ?? ''}',
        createdAt: json['created_at'] as String?,
      );
}

/// 一步的 token 用量（ADR-0088 §2.5：`{prompt, completion, total}`）。
class StepUsage {
  final int prompt;
  final int completion;
  final int total;

  const StepUsage({this.prompt = 0, this.completion = 0, this.total = 0});

  factory StepUsage.fromJson(Map<String, dynamic> json) => StepUsage(
        prompt: _asInt(json['prompt']),
        completion: _asInt(json['completion']),
        total: _asInt(json['total']),
      );
}

/// 运行内一步（全步骤投影的最小单元）。
///
/// 对应后端 `ai/schemas.MessageResp`。安全标记（`input_safe`/`output_safe`/
/// `blocked`/`block_reason`）本票**只透传不渲染**——脱敏与破窗归 ticket 03；
/// 但字段现在就解析，届时前端直接消费，不必再改数据层。
class RunTraceStep {
  final String id;

  /// 步序号（回放顺序）。
  final int turn;

  /// `system` / `user` / `assistant` / `tool`（谁产生）。
  final String role;

  /// `input` / `routing` / `tool_call` / `tool_result` / `generation` / `output` /
  /// `error`（运行到哪一步）。
  final String step;

  /// 人类可读内容（原文；脱敏归 ticket 03）。
  final String content;

  /// 本步模型（01 落库后非空）。
  final String? model;

  /// 本步耗时（毫秒，01 落库后非空）。
  final int? latencyMs;

  /// 本步 token（01 落库后非空）。
  final StepUsage? usage;

  final bool inputSafe;
  final bool outputSafe;
  final bool blocked;
  final String? blockReason;

  const RunTraceStep({
    required this.id,
    this.turn = 0,
    this.role = '',
    this.step = '',
    this.content = '',
    this.model,
    this.latencyMs,
    this.usage,
    this.inputSafe = true,
    this.outputSafe = true,
    this.blocked = false,
    this.blockReason,
  });

  factory RunTraceStep.fromJson(Map<String, dynamic> json) => RunTraceStep(
        id: '${json['id']}',
        turn: _asInt(json['turn']),
        role: '${json['role'] ?? ''}',
        step: '${json['step'] ?? ''}',
        content: (json['content'] as String?) ?? '',
        model: json['model'] as String?,
        latencyMs: (json['latency_ms'] as num?)?.toInt(),
        usage: json['usage'] is Map
            ? StepUsage.fromJson((json['usage'] as Map).cast<String, dynamic>())
            : null,
        // 缺省按「未评估」处理：安全闸门是后端默认放行的，缺列不等于被拦。
        inputSafe: json['input_safe'] as bool? ?? true,
        outputSafe: json['output_safe'] as bool? ?? true,
        blocked: json['blocked'] as bool? ?? false,
        blockReason: json['block_reason'] as String?,
      );
}

/// 一次运行的详情：概要 + 全部步骤（按 turn 正序）。
class RunTraceDetail {
  final RunTraceRun run;
  final List<RunTraceStep> steps;

  const RunTraceDetail({required this.run, this.steps = const <RunTraceStep>[]});

  factory RunTraceDetail.fromJson(Map<String, dynamic> json) => RunTraceDetail(
        run: RunTraceRun.fromJson(
            (json['conversation'] as Map).cast<String, dynamic>()),
        steps: [
          for (final raw in (json['messages'] as List? ?? const []))
            if (raw is Map) RunTraceStep.fromJson(raw.cast<String, dynamic>()),
        ],
      );
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

/// kind → 教师口径标签。后端 kind 是开放字符串，认不出的原样显示。
///
/// 收口在领域层而不是各视图私写：轨迹列表与轨迹详情都渲染它，写两遍迟早出现
/// 「两个面板对不上」的排障事故（同后端 `trace.py` 的口径收口理由）。
String runKindLabel(String kind) => switch (kind) {
      'query' => '答疑',
      'question' => '出题',
      'grade' => '批改',
      'tutor' => '伴学',
      'agent' => '智能体',
      final other => other.isEmpty ? '运行' : other,
    };
