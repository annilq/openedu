import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/assistant_card.dart';
import 'assistant_card_header.dart';

/// 提示卡（notice / 空结果 / 未登记种类的降级）。
///
/// 三种来源共用一张卡是因为它们**排版完全一致**（标题 + 一句文本），
/// 区别只有文本颜色：`notice` 是坏消息（查询失败），走语义 error 前景，
/// 不能和普通空结果同色——同色就会把「没查到」说成「查到了，是空的」。
class AssistantTextCard extends StatelessWidget {
  final AssistantCard card;

  const AssistantTextCard({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (card.title.isNotEmpty)
          AssistantCardHeader(
            title: card.title,
            subject: card.subject,
            kind: card.kind,
          ),
        if (card.title.isNotEmpty && card.text.isNotEmpty)
          const SizedBox(height: AppSpacing.sm),
        if (card.text.isNotEmpty)
          Text(
            card.text,
            style: text.bodyMedium?.copyWith(
              color: card.kind == AssistantCardKind.notice
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
