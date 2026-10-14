import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';

/// 「我的」页内系统分区的一行可点入口（ticket 08）：图标 + 名称 + 右箭头。
///
/// 走 [AppFocusableAction]（键盘可达），与「账号信息」的 [_InfoRow] 排版语言一致；
/// [onTap] 为空时整行不可操作（学生端不传回调 → 分区不渲染，更不会渲染空行）。
///
/// 从 `profile_screen.dart` 抽出（ADR-0058 棘轮）：profile_screen 已逼近 400 行软上限，
/// 把这一独立视觉件拆到自己的文件，让「我的」页回到单一职责、主文件回到阈值内。
class SystemNavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const SystemNavRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppFocusableAction(
      onTap: onTap,
      semanticLabel: label,
      hoverHighlight: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: app.primary),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: text.bodyLarge?.copyWith(color: app.onSurface),
            ),
            const Spacer(),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: app.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
