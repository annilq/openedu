/// 助手空态的推荐操作（ADR-0072 / ADR-0089）。
///
/// 由服务端按上下文从固定目录装配（非 LLM 生成）：
/// - [kind]=='prompt'：[payload] 是预置提示文本，前端点击即 `send(payload, courseware: ctx)`。
/// - [kind]=='navigate'：[payload] 是既有 `ShellDestination` 枚举，点击走壳导航。
/// 出题（含判断题）与答疑统一走自然语言入口：判断题由出题子代理从文本自主判定
/// （ADR-0089），不再有 quiz 旗标。
class SuggestedAction {
  final String label;
  final String kind;
  final String payload;

  const SuggestedAction({
    required this.label,
    required this.kind,
    required this.payload,
  });

  factory SuggestedAction.fromJson(Map<String, dynamic> json) => SuggestedAction(
        label: json['label'] as String,
        kind: json['kind'] as String,
        payload: json['payload'] as String,
      );
}
