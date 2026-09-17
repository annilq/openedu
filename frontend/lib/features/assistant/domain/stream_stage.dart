/// 把 AG-UI 编排帧折成「阶段文案」的纯模块（助手气泡与出题流程共用）。
///
/// 背景：后端在正文首 token 之前就会推送一串编排帧——路由 THINKING
///（「正在理解你的需求…」「已选择助手：X」）与 TOOL_CALL/TOOL_RESULT（模型
/// 先查数据再作答，一轮 = 一次完整 LLM 往返）。这些帧此前被各 fold 直接丢弃，
/// 用户只能盯着一个静态「思考中」转圈，感觉等待远比实际生成时间长。
///
/// 这里把「哪些帧算阶段、文案怎么取」收口成一个纯函数，供 `AiTextFold` 与
/// `QuestionGenFold` 复用——两处对同一帧序列必须给出同一份阶段文案。
///
/// 只收「编排/工具」帧；模型思维链 THINKING（无 routing 标记、逐块流入）
/// **不算阶段**——把它当文案会让气泡文字高频闪烁，且内容是内部独白。
library;

import 'assistant_event.dart';

/// 从一帧事件提取阶段文案；null 表示该帧不改变阶段。
///
/// - 路由 THINKING（extra.routing）：直接用后端文案（「正在理解你的需求…」等）。
/// - TOOL_CALL：优先可读标签（后端 ToolSpec.label，如「查询掌握度」）；无标签时
///   兜底通用文案——绝不把裸工具名（`get_mastery`）亮给用户。
/// - TOOL_RESULT：工具已执行完、模型正在组织答案，切到收尾文案。
String? stageOfEvent(AssistantEvent ev) => switch (ev.eventType) {
      AssistantEventType.thinking =>
        (ev.extra?['routing'] == true || ev.extra?['business'] != null)
            ? (ev.text ?? _fallback)
            : null,
      AssistantEventType.toolCall => ev.label != null
          ? '正在${ev.label}'
          : _fallback,
      AssistantEventType.toolResult => _wrapping,
      _ => null,
    };

const _fallback = '正在思考…';
const _wrapping = '正在整理结果…';
