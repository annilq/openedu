import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
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
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.sentiment_dissatisfied_rounded,
                size: 48,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '暂时出了点小问题',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                onPressed: onRetry,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Text(retryLabel),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
