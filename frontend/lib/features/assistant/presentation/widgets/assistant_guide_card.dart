import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../domain/assistant_card.dart';
import 'assistant_card_header.dart';

/// 引导卡：一句「为什么不能」+ 一个（或几个）**受控跳转出口**。
///
/// 这张卡补的是这条链路上唯一真正断掉的一环：助手是只读的（不是缺陷，是边界），
/// 但「你不能做」不该是终点——用户需要下一步。在此之前后端只能回一句
/// 「请到『任务/作业』页面操作」，而卡片协议里**没有任何位置**能放那个入口，
/// 于是用户被告知去别处、却拿不到别处。
///
/// [onAction] 为 null 时不渲染出口：只读回放里没人接这个动作，
/// 给一个点不动的按钮比不给更糟（会让人以为界面坏了）。
class AssistantGuideCard extends StatelessWidget {
  final AssistantCard card;
  final void Function(AssistantCardAction action)? onAction;

  const AssistantGuideCard({super.key, required this.card, this.onAction});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    // 出口按「宿主给没给处理器」决定要不要画：给不出落点的按钮不如不画。
    final buttons = <Widget>[];
    final handler = onAction;
    if (handler != null) {
      for (final action in card.actions) {
        buttons.add(
          AppPrimaryButton(
            label: action.label,
            fullWidth: false,
            onPressed: () => handler(action),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AssistantCardHeader(
          title: card.title,
          subject: card.subject,
          kind: card.kind,
        ),
        if (card.text.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            card.text,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          // 并排按钮一律 Wrap：ShadButton 放进会压缩它的容器（Row/Expanded）
          // 会 RenderFlex overflowed——卡片在消息流里宽度有限，尤其容易撞上。
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: buttons,
          ),
        ],
      ],
    );
  }
}
