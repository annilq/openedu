import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// 通用错误占位组件：友好的图标 + 居中排版 + 重试按钮。
class AppError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AppError({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = '重试',
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: app.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                LucideIcons.alertCircle,
                size: 48,
                color: app.onErrorContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '暂时出了点小问题',
              style: AppTheme.textOf(context).titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.textOf(context).bodyLarge?.copyWith(
                    color: app.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              ShadButton(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                onPressed: onRetry,
                leading: const Icon(LucideIcons.refreshCcw, size: 18),
                child: Text(
                  retryLabel,
                  style: AppTheme.textOf(context).labelMedium?.copyWith(
                        color: app.onPrimary,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}