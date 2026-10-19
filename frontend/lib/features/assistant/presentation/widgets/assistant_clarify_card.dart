import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../domain/assistant_clarify.dart';

/// 缺槽追问的**一句式快捷入口**（ADR-0095 / ADR-0100）。
///
/// 后端在**普通** ASSISTANT_MESSAGE 帧的 `extra.clarify` 下发仍缺的必填槽（不新增
/// 事件类型）。气泡正文本身已经把这句引导念完了（「还差科目、年级、题型——可以一次
/// 说完，例如……」），本卡只补一件事：**给那句示例做成可点的一行**，不想打字的
/// 用户点一下就把整句发出去，一次补齐全部缺槽。
///
/// ## 为什么不再渲染选项 chip（ADR-0100）
///
/// 旧实现给每个缺槽铺一组取值 chip（科目一排 / 年级一排 / 题型一排），点一个只回传
/// **一个**槽的值——补三项要点三次往返。而预检层按正则一次就能抽满多个槽，用户一句
/// 「三年级数学选择题」本来就够。把追问做成表单，等于用 UI 把「一句话能说完的事」
/// 拆成三次，比纯文本更慢，也与用户的实际输入习惯相反。
///
/// 结构化载荷（`clarify.missing_slots`）**仍然下发**：它是协议（历史回放、汇总卡、
/// 读屏都依赖它），本次只改渲染方式，不改协议。
class AssistantClarifyCard extends StatelessWidget {
  final List<ClarifySlot> slots;

  /// 把示例句当作一条用户消息发出（与 follow-up chips 同一条通路）。
  final void Function(String payload) onPrompt;

  const AssistantClarifyCard({
    super.key,
    required this.slots,
    required this.onPrompt,
  });

  /// 可点即发的示例句：与后端 `slot_clarify._EXAMPLE` 同一句。
  ///
  /// 为什么前端也留一份：后端把它念在正文里，前端把它变成按钮，两处必须是同一句，
  /// 否则「念的示例」与「点下去的文本」不一致。一致性由测试锁定。
  static const String example = '三年级数学、选择题、5 道';

  /// 能由 [example] 一次补齐的槽集合。
  ///
  /// 只有出题意图（`intent_schemas.generate`）有必填槽，也正是这几项。其它业务
  /// 将来若加必填槽，示例句就不再适用——此时**不渲染本卡**，正文的话术仍然够用，
  /// 不会出现「点一句补错了值」。
  static const Set<String> _exampleSlots = <String>{
    'subject',
    'grade',
    'qtype',
    'count',
  };

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const SizedBox.shrink();
    // 缺了示例覆盖不到的槽 → 只留正文引导，不给会补错值的按钮。
    if (!slots.every((s) => _exampleSlots.contains(s.name))) {
      return const SizedBox.shrink();
    }
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.sm, AppSpacing.xl2, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppFocusableAction(
          onTap: () => onPrompt(example),
          semanticLabel: '一次补齐：$example',
          borderRadius: BorderRadius.circular(999),
          hoverHighlight: true,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs2,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceRaised,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: scheme.outline,
                width: AppElevation.borderWidthHairline,
              ),
            ),
            child: Text(
              '一句补齐：$example',
              style: text.labelMedium?.copyWith(color: scheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}
