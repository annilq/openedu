import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/material.dart';

import '../../../../../shared/theme/app_theme.dart';

/// 生成中面板（ADR-0017）：当前题的内联推理区，题卡到达后由 `_PreviewCard` 替代。
///
/// 渲染层退化为对 [reasoning] 的忠实映射：后端已增量下发 THINKING，
/// 前端无需自有定时器（原 [ReasoningTypewriterWidget] 的自定时 Timer 与事件到达解耦，
/// 导致生成期 `_shown` 永不前进、题卡到达后全文闪现）。[streaming] 期间末尾挂 `▌`
/// 光标，表示仍在揭示；[reasoning] 为空（首个增量到达前）显示占位文案。
class PreviewGenerating extends StatelessWidget {
  final int index;
  final String label;
  final String reasoning;
  final bool streaming;

  const PreviewGenerating({
    super.key,
    required this.index,
    required this.label,
    required this.reasoning,
    required this.streaming,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surface,
        borderRadius: BorderRadius.circular(AppRadius.bubble),
        border: Border.all(color: app.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: app.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text('第 $index 题 · 生成中',
                    style: text.labelSmall?.copyWith(
                        color: app.onPrimaryContainer,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (label.isNotEmpty)
                Expanded(
                  child: Text(
                    label,
                    style: text.labelSmall?.copyWith(color: app.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // 首个推理增量到达前给占位文案，避免内联区出现一段空白。
          if (reasoning.isEmpty)
            Text(
              '正在构思出题思路…',
              style: text.bodySmall?.copyWith(
                color: app.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            // 忠实映射：直接渲染已增量下发的推理全文，[streaming] 时挂光标。
            Text(
              reasoning + (streaming ? '▌' : ''),
              style: text.bodySmall?.copyWith(
                color: app.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
