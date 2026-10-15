import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/assistant_clarify.dart';
import 'assistant_slot_input.dart';

/// 缺槽引导输入卡（ADR-0095）。
///
/// 后端在**普通** ASSISTANT_MESSAGE 帧的 `extra.clarify` 下发仍缺的必填槽（不新增
/// 事件类型），前端据此渲染可点选 / 可输入的引导卡：枚举与带范围的 int 出选项 chips，
/// 其余出输入框。选定后把值当作一条新的用户消息发出（复用 `onPrompt`），后端下一轮
/// 合并该槽继续——用户既不用猜措辞，也不必把整条需求重打一遍。
///
/// 取值控件本身在 [AssistantSlotInput]（与汇总卡的「修改」共用），本卡只负责组织
/// 话术与排版。
class AssistantClarifyCard extends StatelessWidget {
  final List<ClarifySlot> slots;

  /// 把选定/输入的值当作一条用户消息发出（与 follow-up chips 同一条通路）。
  final void Function(String payload) onPrompt;

  const AssistantClarifyCard({
    super.key,
    required this.slots,
    required this.onPrompt,
  });

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const SizedBox.shrink();
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.sm, AppSpacing.xl2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '还差这些信息：',
            style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final slot in slots) _SlotField(slot: slot, onPrompt: onPrompt),
        ],
      ),
    );
  }
}

/// 单个缺槽：话术 + 取值控件。
class _SlotField extends StatelessWidget {
  final ClarifySlot slot;
  final void Function(String payload) onPrompt;

  const _SlotField({required this.slot, required this.onPrompt});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.prompt.isEmpty ? '请补充：${slot.name}' : slot.prompt,
            style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs2),
          AssistantSlotInput(slot: slot, onPrompt: onPrompt),
        ],
      ),
    );
  }
}
