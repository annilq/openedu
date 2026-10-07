/// 助手空态的推荐操作（ADR-0072）。
///
/// 由服务端按上下文从固定目录装配（非 LLM 生成）：
/// - [kind]=='prompt'：[payload] 是预置提示文本，前端点击即 `send(payload, courseware: ctx)`。
/// - [kind]=='navigate'：[payload] 是既有 `ShellDestination` 枚举，点击走壳导航。
/// - [quiz] 为真时 prompt 动作触发出题-判断-引导闭环（`send(payload, quiz: true)`）。
class SuggestedAction {
  final String label;
  final String kind;
  final String payload;
  final bool quiz;

  const SuggestedAction({
    required this.label,
    required this.kind,
    required this.payload,
    this.quiz = false,
  });

  factory SuggestedAction.fromJson(Map<String, dynamic> json) => SuggestedAction(
        label: json['label'] as String,
        kind: json['kind'] as String,
        payload: json['payload'] as String,
        quiz: json['quiz'] as bool? ?? false,
      );
}
