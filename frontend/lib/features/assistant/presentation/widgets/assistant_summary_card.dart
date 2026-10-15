import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../domain/assistant_summary.dart';
import 'assistant_slot_input.dart';

/// 「已确认规格」汇总卡（ADR-0095）：出題前把已填项与被默认填充的项念给用户听，
/// 并给每一项一个「修改」入口。
///
/// 为什么要有这张卡：英文码与默认值对用户是隐形的——「题型=choice、难度=medium」
/// 念出来等于没给修正机会（US5）。逐项列出 + 可改，用户才有「生成前修正」的落点。
///
/// 修改即**再发一条用户消息**：后端下一轮按同一套规则合并（新值覆盖旧值）并重出，
/// 无需任何新的协议或状态。取值控件与澄清卡共用 [AssistantSlotInput]。
class AssistantSummaryCard extends StatefulWidget {
  final List<SummarySlot> slots;

  /// 把修改后的值当作一条用户消息发出（与 follow-up chips 同一条通路）。
  final void Function(String payload) onPrompt;

  const AssistantSummaryCard({
    super.key,
    required this.slots,
    required this.onPrompt,
  });

  @override
  State<AssistantSummaryCard> createState() => _AssistantSummaryCardState();
}

class _AssistantSummaryCardState extends State<AssistantSummaryCard> {
  /// 当前展开修改控件的槽名（一次只改一项，避免满屏输入框）。
  final Set<String> _editing = <String>{};

  @override
  Widget build(BuildContext context) {
    if (widget.slots.isEmpty) return const SizedBox.shrink();
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.sm, AppSpacing.xl2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已确认规格：',
            style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final slot in widget.slots)
            _SummaryRow(
              slot: slot,
              editing: _editing.contains(slot.slot.name),
              onToggleEdit: () => setState(() {
                final name = slot.slot.name;
                if (!_editing.remove(name)) _editing.add(name);
              }),
              onPrompt: (v) {
                setState(() => _editing.remove(slot.slot.name));
                widget.onPrompt(v);
              },
            ),
        ],
      ),
    );
  }
}

/// 单行：标签 + 当前值 + 「修改」入口（展开后是取值控件）。
class _SummaryRow extends StatelessWidget {
  final SummarySlot slot;
  final bool editing;
  final VoidCallback onToggleEdit;
  final void Function(String payload) onPrompt;

  const _SummaryRow({
    required this.slot,
    required this.editing,
    required this.onToggleEdit,
    required this.onPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                slot.label.isEmpty ? slot.slot.name : slot.label,
                style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  slot.valueLabel.isEmpty ? '（未指定）' : slot.valueLabel,
                  style: text.labelMedium?.copyWith(color: scheme.onSurface),
                ),
              ),
              if (slot.canEdit)
                AppFocusableAction(
                  onTap: onToggleEdit,
                  semanticLabel: '修改${slot.label}',
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xs2),
                    child: Text(
                      editing ? '收起' : '修改',
                      style: text.labelMedium?.copyWith(color: scheme.primary),
                    ),
                  ),
                ),
            ],
          ),
          if (editing) ...[
            const SizedBox(height: AppSpacing.xs2),
            AssistantSlotInput(slot: slot.slot, onPrompt: onPrompt),
          ],
        ],
      ),
    );
  }
}
