import 'package:flutter/widgets.dart';

import '../../domain/assistant_card.dart';
import 'assistant_card_shell.dart';
import 'assistant_guide_card.dart';
import 'assistant_list_card.dart';
import 'assistant_question_card.dart';
import 'assistant_stats_card.dart';
import 'assistant_text_card.dart';

/// AI 消息里的结构化卡片（ADR-0042）：按 [AssistantCard.kind] 分派版式。
///
/// 本文件**只做分派**——九种卡片各在自己的文件里（`assistant_*_card.dart`），
/// 因为「9 种卡片拼在一个文件」正是 ADR-0058 §2 点名的反例。
///
/// 五条版式覆盖全部种类：
/// - [AssistantCardKind.question] → 题目卡（学科/题型/难度 + 题干 + 选项 + 答案 + 解析 + 出题思路）
/// - [AssistantCardKind.progress] → 指标卡（答对 / 正确率 / 打卡）
/// - [AssistantCardKind.notice] → 提示卡（标题 + 文本）
/// - [AssistantCardKind.guide] → 引导卡（说明 + 受控跳转出口）
/// - 其余列表类 → 列表卡（标题 + 归属 + 明细行）
///
/// **降级不丢内容**：认不出的种类若带 `items` 走列表卡的「通用行」，否则走提示卡。
/// v1 只认 `{type, subject, stem}` 且 `stem` 为空即 `SizedBox.shrink()`——新卡片
/// 到了前端会整张静默消失。
///
/// 卡片在气泡**外侧**（见 [AssistantMessageList]）：卡片自带 surface 底与描边，
/// 套在气泡里是双层容器。
class AssistantCardTile extends StatelessWidget {
  final AssistantCard card;

  /// 卡片动作出口（目前只有引导卡的 [AssistantCard.actions] 会用）。
  ///
  /// 由页面注入而不是卡片自己去 `Navigator.push`：同一条卡片在家长端是 push 的
  /// 整页、在娃娃端是壳内页签，**怎么退、退到哪只有宿主知道**。
  /// 传 null（如只读回放）时按钮不渲染——点不动的按钮比没有按钮更糟。
  final void Function(AssistantCardAction action)? onAction;

  const AssistantCardTile({super.key, required this.card, this.onAction});

  @override
  Widget build(BuildContext context) {
    if (!card.hasContent) return const SizedBox.shrink();
    final Widget body = switch (card.kind) {
      // 题目卡左侧学科色条由 Row(stretch) 撑满卡片高度；卡片高度随内容，
      // 消息流内高度无界，须 IntrinsicHeight 给 Row 一个有界高度。
      AssistantCardKind.question =>
        IntrinsicHeight(child: AssistantQuestionCard(card: card)),
      AssistantCardKind.progress => AssistantStatsCard(card: card),
      AssistantCardKind.notice => AssistantTextCard(card: card),
      AssistantCardKind.guide =>
        AssistantGuideCard(card: card, onAction: onAction),
      _ => card.items.isEmpty
          ? AssistantTextCard(card: card)
          : AssistantListCard(card: card),
    };
    return AssistantCardShell(child: body);
  }
}
