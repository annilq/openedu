import 'assistant_card.dart';
import 'assistant_event.dart';
import 'stream_stage.dart';

/// 把 AG-UI 事件流折成「AI 文本 + 结构化卡片 + 安全兜底标记」的纯模块。
///
/// 解释规则原先写在 `assistant_notifier` 与已删除的 `tutor_notifier` 各自的
/// `await for` 循环里：两处语义完全一致（增量文本累加 / DATA 挂卡片 /
/// INPUT_UNSAFE 标拦截），但逐帧逻辑夹在 Riverpod 状态与 SSE 之间，无法断言。
/// 这里把它收敛成一个不可变值 + 一个 [apply]，测试直接喂事件列表即可。
/// （ADR-0036 后只剩 `assistant_notifier` 一个消费方。）
///
/// 卡片不在这里解释字段——只做「信封 → [AssistantCard]」的解析（ADR-0042），
/// 种类分派与排版在渲染层（`presentation/widgets/assistant_cards.dart`）。
///
/// 不关心的帧（THINKING / TOOL_CALL / TOOL_RESULT / STEP / RUN_STARTED / DONE）
/// 一律原样返回 [AiTextFold.apply] 的接收者：对话气泡不单独渲染它们。
class AiTextFold {
  /// 已累积的 AI 正文（ASSISTANT_MESSAGE 增量拼接结果）。
  final String text;

  /// DATA 帧带下的类型化卡片（题卡 / 任务卡 / 学情卡）。
  final List<AssistantCard> cards;

  /// 是否因安全兜底（ERROR.code == INPUT_UNSAFE）。
  final bool blocked;

  /// 当前阶段文案（路由 THINKING / TOOL_CALL / TOOL_RESULT 提取，见
  /// [stageOfEvent]）：正文到达前渲染进占位气泡，替代静态「思考中…」。
  /// 取「最近一帧」而非累积——阶段是瞬时状态，不是日志。
  final String stage;

  /// ERROR 帧文案；非 null 表示流以错误收尾。
  final String? errorText;

  const AiTextFold({
    this.text = '',
    this.cards = const <AssistantCard>[],
    this.blocked = false,
    this.stage = '',
    this.errorText,
  });

  static const _fallbackError = '出错了，请稍后重试';

  bool get hasError => errorText != null;

  /// 还没有任何可渲染内容——调用方据此决定是否显示「思考中」占位气泡。
  bool get isEmpty => text.isEmpty && cards.isEmpty && !hasError;

  /// 消费一帧事件，返回新的 [AiTextFold]（纯函数，不改接收者）。
  AiTextFold apply(AssistantEvent ev) {
    // 阶段帧与内容帧可能同帧类不同语义：阶段提取先行，内容分支照旧。
    final stage = stageOfEvent(ev);
    return switch (ev.eventType) {
      AssistantEventType.assistantMessage =>
        _copy(text: text + (ev.text ?? ''), stage: stage),
      AssistantEventType.data => _withCard(ev, stage: stage),
      AssistantEventType.error => _copy(
          blocked: blocked || ev.code == AssistantErrorCode.inputUnsafe,
          errorText: errorText ?? ev.message ?? _fallbackError,
        ),
      _ => stage == null ? this : _copy(stage: stage),
    };
  }

  AiTextFold _withCard(AssistantEvent ev, {String? stage}) {
    final card = AssistantCard.fromData(ev.data);
    // 畸形帧（result 不是对象）与「无任何字段」的卡都不挂：不制造空气泡。
    if (card == null || !card.hasContent) {
      return stage == null ? this : _copy(stage: stage);
    }
    return _copy(
      cards: <AssistantCard>[...cards, card],
      stage: stage,
    );
  }

  AiTextFold _copy({
    String? text,
    List<AssistantCard>? cards,
    bool? blocked,
    String? stage,
    Object? errorText = _unset,
  }) =>
      AiTextFold(
        text: text ?? this.text,
        cards: cards ?? this.cards,
        blocked: blocked ?? this.blocked,
        stage: stage ?? this.stage,
        errorText: identical(errorText, _unset)
            ? this.errorText
            : errorText as String?,
      );

  static const _unset = Object();
}
