import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/assistant_card.dart';
import '../../domain/card_payload.dart';
import 'assistant_card_header.dart';

/// 指标卡（progress）：答对 / 正确率 / 打卡。
///
/// 数字一律走 [cardStatsOf]，与复制纯文本同一份——卡片上看到 `8/10`
/// 却复制到 `10` 这种漂移不该出现。
class AssistantStatsCard extends StatelessWidget {
  final AssistantCard card;

  const AssistantStatsCard({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final stats = cardStatsOf(card);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AssistantCardHeader(
          title: card.title,
          subject: card.subject,
          kind: card.kind,
        ),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xxl,
            runSpacing: AppSpacing.md,
            children: [for (final s in stats) _StatCell(value: s.$1, label: s.$2)],
          ),
        ],
        if (card.text.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            card.text,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// 一个指标：数字在上、名字在下。
class _StatCell extends StatelessWidget {
  final String value;
  final String label;

  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        Text(
          label,
          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
