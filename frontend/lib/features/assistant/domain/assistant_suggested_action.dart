/// 助手空态的推荐操作（ADR-0072 / ADR-0089）。
///
/// 由服务端按上下文从固定目录装配（非 LLM 生成）：
/// - [kind]=='prompt'：[payload] 是预置提示文本，前端点击即 `send(payload, ...)`。
/// - [kind]=='navigate'：[payload] 是既有 `ShellDestination` 枚举，点击走壳导航。
/// 出题（含判断题）与答疑统一走自然语言入口：判断题由出题子代理从文本自主判定
/// （ADR-0089），不再有 quiz 旗标。
///
/// [action] 非空表示「这条入口的意图服务端已经知道」：点击时连同文本回传，路由走
/// 动作直配（ADR-0081）而不是让模型从短句里猜业务。它同时是会话中途切换意图的
/// 显式信号——用户点 chip 就是在切换。出题类 chip 都带 `task_generate`。
class SuggestedAction {
  final String label;
  final String kind;
  final String payload;
  final String? action;

  const SuggestedAction({
    required this.label,
    required this.kind,
    required this.payload,
    this.action,
  });

  factory SuggestedAction.fromJson(Map<String, dynamic> json) => SuggestedAction(
        label: json['label'] as String,
        kind: json['kind'] as String,
        payload: json['payload'] as String,
        action: json['action'] as String?,
      );
}
