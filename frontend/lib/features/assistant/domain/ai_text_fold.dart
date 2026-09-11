import 'assistant_event.dart';

/// 把 AG-UI 事件流折成「AI 文本 + 结构化卡片 + 安全兜底标记」的纯模块。
///
/// 解释规则原先写在 `assistant_notifier` 与 `tutor_notifier` 各自的 `await for`
/// 循环里：两处语义完全一致（增量文本累加 / DATA 挂卡片 / INPUT_UNSAFE 标拦截），
/// 但逐帧逻辑夹在 Riverpod 状态与 SSE 之间，无法断言。这里把它收敛成一个不可变
/// 值 + 一个 [apply]，测试直接喂事件列表即可。
///
/// 不关心的帧（THINKING / TOOL_CALL / TOOL_RESULT / STEP / RUN_STARTED / DONE）
/// 一律原样返回 [AiTextFold.apply] 的接收者：对话气泡不单独渲染它们。
class AiTextFold {
  /// 已累积的 AI 正文（ASSISTANT_MESSAGE 增量拼接结果）。
  final String text;

  /// DATA 帧带下的结构化结果（题卡 / 任务卡 / 学情卡）。
  final List<Map<String, dynamic>> cards;

  /// 是否因安全兜底（ERROR.code == INPUT_UNSAFE）。
  final bool blocked;

  /// ERROR 帧文案；非 null 表示流以错误收尾。
  final String? errorText;

  const AiTextFold({
    this.text = '',
    this.cards = const <Map<String, dynamic>>[],
    this.blocked = false,
    this.errorText,
  });

  static const _fallbackError = '出错了，请稍后重试';

  bool get hasError => errorText != null;

  /// 还没有任何可渲染内容——调用方据此决定是否显示「思考中」占位气泡。
  bool get isEmpty => text.isEmpty && cards.isEmpty && !hasError;

  /// 消费一帧事件，返回新的 [AiTextFold]（纯函数，不改接收者）。
  AiTextFold apply(AssistantEvent ev) => switch (ev.eventType) {
        AssistantEventType.assistantMessage =>
          _copy(text: text + (ev.text ?? '')),
        AssistantEventType.data => _withCard(ev),
        AssistantEventType.error => _copy(
            blocked: blocked || ev.code == AssistantErrorCode.inputUnsafe,
            errorText: errorText ?? ev.message ?? _fallbackError,
          ),
        _ => this,
      };

  AiTextFold _withCard(AssistantEvent ev) {
    final result = ev.data?['result'];
    if (result is! Map<String, dynamic>) return this;
    return _copy(cards: <Map<String, dynamic>>[...cards, result]);
  }

  AiTextFold _copy({
    String? text,
    List<Map<String, dynamic>>? cards,
    bool? blocked,
    Object? errorText = _unset,
  }) =>
      AiTextFold(
        text: text ?? this.text,
        cards: cards ?? this.cards,
        blocked: blocked ?? this.blocked,
        errorText: identical(errorText, _unset)
            ? this.errorText
            : errorText as String?,
      );

  static const _unset = Object();
}
