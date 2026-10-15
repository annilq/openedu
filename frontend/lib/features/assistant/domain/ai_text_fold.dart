import 'assistant_card.dart';
import 'assistant_clarify.dart';
import 'assistant_event.dart';
import 'assistant_source.dart';
import 'assistant_suggested_action.dart';
import 'assistant_summary.dart';
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
/// 不关心的帧（USER_MESSAGE / THINKING / TOOL_CALL / TOOL_RESULT / STEP /
/// RUN_STARTED / DONE）一律原样返回 [AiTextFold.apply] 的接收者：对话气泡不单独
/// 渲染它们。其中 USER_MESSAGE 是运行时回显（客户端已本地添加用户气泡），
/// 路由 THINKING（extra.routing）只作阶段文案（见 [stageOfEvent]），都不进正文。
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

  /// 答疑引用落点（后端 `rag_sources` DATA 帧）：答案下方「参考来源」条的数据。
  final List<RagSource> sources;

  /// 回复后 follow-up chips（后端 `SUGGESTED_ACTIONS` 帧，ADR-0072 修订 / 票 03(a)）。
  ///
  /// 服务端固定目录、非 LLM；仅入口、不落库。附在本轮最后一条 ai 消息下方渲染。
  final List<SuggestedAction> suggestedActions;

  /// 缺失的必填槽（后端 ASSISTANT_MESSAGE 帧的 `extra.clarify`，ADR-0095）。
  ///
  /// 澄清**不新增事件类型**：它是一条普通助手消息，只是 `extra` 里多带了缺槽清单。
  /// 前端据此渲染引导输入卡；空列表 = 本轮不是澄清，按普通正文渲染。
  final List<ClarifySlot> clarifySlots;

  /// 「已确认规格」汇总槽（同一帧类的 `extra.summary`，ADR-0095）。
  ///
  /// 与澄清互斥：一轮要么缺槽要澄清、要么齐备发汇总。前端据此渲染带「修改」入口的
  /// 汇总卡，让用户在生成前有机会改被默认填充的项（US5）。
  final List<SummarySlot> summarySlots;

  const AiTextFold({
    this.text = '',
    this.cards = const <AssistantCard>[],
    this.blocked = false,
    this.stage = '',
    this.errorText,
    this.sources = const <RagSource>[],
    this.suggestedActions = const <SuggestedAction>[],
    this.clarifySlots = const <ClarifySlot>[],
    this.summarySlots = const <SummarySlot>[],
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
      AssistantEventType.assistantMessage => _withAssistantMessage(ev, stage: stage),
      AssistantEventType.data => _withData(ev, stage: stage),
      AssistantEventType.error => _copy(
          blocked: blocked || ev.code == AssistantErrorCode.inputUnsafe,
          errorText: errorText ?? ev.message ?? _fallbackError,
        ),
      // 运行时编排帧：用户消息回显（T07 起判断题闭环也走运行时，会下发 USER_MESSAGE，
      // 与本地已添加的用户气泡重复）——绝不当正文，否则用户那句话会被渲染两遍。
      AssistantEventType.userMessage => this,
      AssistantEventType.suggestedActions => _withSuggestedActions(ev),
      _ => stage == null ? this : _copy(stage: stage),
    };
  }

  /// 澄清帧（ADR-0095）：正文照常累加（它是各缺槽 prompt 拼成的普通句子），同时把
  /// `extra.clarify.missing_slots` 收进来供渲染层出引导输入卡。
  ///
  /// 本轮后续帧若不带 clarify 则**维持**已有列表（一问一帧，不重复叠加）。
  AiTextFold _withAssistantMessage(AssistantEvent ev, {String? stage}) {
    final slots = ClarifySlot.slotsOfEvent(ev);
    final summary = SummarySlot.slotsOfEvent(ev);
    return _copy(
      text: text + (ev.text ?? ''),
      stage: stage,
      clarifySlots: slots.isEmpty ? null : slots,
      summarySlots: summary.isEmpty ? null : summary,
    );
  }

  AiTextFold _withData(AssistantEvent ev, {String? stage}) {
    final data = ev.data;
    // 答疑引用条：把 `rag_sources` DATA 帧收进 sources，供答案下方渲染。
    // 与卡片走同一信封（DATA），但种类不同、渲染器不同，故在此分流。
    if (data != null &&
        data['type'] == 'rag_sources' &&
        data['result'] is List) {
      final incoming = (data['result'] as List)
          .whereType<Map<String, dynamic>>()
          .map(RagSource.fromJson)
          .toList();
      if (incoming.isNotEmpty) {
        return _copy(
          sources: <RagSource>[...sources, ...incoming],
          stage: stage,
        );
      }
    }
    return _withCard(ev, stage: stage);
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

  AiTextFold _withSuggestedActions(AssistantEvent ev) {
    final data = ev.data;
    if (data == null || data['actions'] is! List) return this;
    final incoming = (data['actions'] as List)
        .whereType<Map<String, dynamic>>()
        .map(SuggestedAction.fromJson)
        .toList();
    if (incoming.isEmpty) return this;
    return _copy(suggestedActions: <SuggestedAction>[...suggestedActions, ...incoming]);
  }

  AiTextFold _copy({
    String? text,
    List<AssistantCard>? cards,
    bool? blocked,
    String? stage,
    Object? errorText = _unset,
    List<RagSource>? sources,
    List<SuggestedAction>? suggestedActions,
    List<ClarifySlot>? clarifySlots,
    List<SummarySlot>? summarySlots,
  }) =>
      AiTextFold(
        text: text ?? this.text,
        cards: cards ?? this.cards,
        blocked: blocked ?? this.blocked,
        stage: stage ?? this.stage,
        errorText: identical(errorText, _unset)
            ? this.errorText
            : errorText as String?,
        sources: sources ?? this.sources,
        suggestedActions: suggestedActions ?? this.suggestedActions,
        clarifySlots: clarifySlots ?? this.clarifySlots,
        summarySlots: summarySlots ?? this.summarySlots,
      );

  static const _unset = Object();
}
