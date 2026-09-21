import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_tags.dart';
import '../../domain/assistant_card.dart';
import '../../domain/card_payload.dart';
import 'assistant_card_header.dart';

/// 列表卡（任务 / 错题 / 到期复习 / 掌握度 / 题库 / 孩子 等带 `items` 的种类）。
///
/// 一种明细一套投影，投影本身在 [cardRowOf]——本文件只管把行画出来，
/// 「哪个字段当主行、哪个当标签」的判断不放在这里，否则复制纯文本那份会跟着漂移。
class AssistantListCard extends StatelessWidget {
  final AssistantCard card;

  const AssistantListCard({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final rows = card.items.map((i) => cardRowOf(card.kind, i)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AssistantCardHeader(
          title: card.title,
          subject: card.subject,
          kind: card.kind,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          Text(
            rows[i].primary,
            style: text.bodyMedium?.copyWith(color: scheme.onSurface),
          ),
          if (rows[i].tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [for (final tag in rows[i].tags) _tagWidget(tag)],
            ),
          ],
        ],
        // 服务端只回前 N 条明细，截断了要说清楚（别让人以为就这几条）。
        if (card.total > rows.length) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '…共 ${card.total} 条',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// 语气 → chip。学科标签走 [AppTags.subject]：色相之外还带几何标记
/// （ADR-0044 三重编码），不靠颜色单独区分学科。
Widget _tagWidget((String, CardTone) tag) => switch (tag.$2) {
      CardTone.info => AppTags.info(tag.$1),
      CardTone.success => AppTags.success(tag.$1),
      CardTone.warning => AppTags.warning(tag.$1),
      CardTone.subject => AppTags.subject(
          SubjectAccent.fromName(tag.$1),
          label: tag.$1,
        ),
      CardTone.normal => AppTags.normal(tag.$1),
    };
