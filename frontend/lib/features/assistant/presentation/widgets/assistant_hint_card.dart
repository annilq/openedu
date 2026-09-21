import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_card.dart';

/// 助手内的空态 / 引导卡（对话空态与历史空态共用同一副骨架）。
///
/// 抽出来不是为了省行数，而是因为这两处**必须是同一个东西**：它们说的是同一句话
/// ——「这里现在什么都没有，可以这样开始」。各写一份的话，改一处尺寸另一处不动，
/// 同一个功能里就会长出两种空态。
class AssistantHintCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  /// 可选行动（如取数失败时的「重试」）。空态是终点，没有行动就该没有这个槽位。
  final Widget? action;

  const AssistantHintCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return PopIn(
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.contentEmpty),
            child: AppCard(
              margin: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 空态图标块：yellow 亮块 + 墨黑字（13.25:1），新粗野撞色强调件。
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppBrutal.yellow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppBrutal.ink, width: AppElevation.borderWidth),
                      boxShadow: AppElevation.hard(),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 36, color: AppBrutal.ink),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(title,
                      textAlign: TextAlign.start,
                      style: text.titleLarge?.copyWith(
                        color: scheme.onSurface,
                      )),
                  const SizedBox(height: AppSpacing.sm),
                  Text(body,
                      textAlign: TextAlign.start,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )),
                  if (action != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
