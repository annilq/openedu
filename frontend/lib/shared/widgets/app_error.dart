import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../exceptions/app_exception.dart';
import '../theme/app_theme.dart';

/// 通用错误占位组件：友好的图标 + 居中排版 + 重试按钮。
///
/// E-Q3=a：若构建参数中提供了错误码 / 传入了 AppException，标题栏下会展示
/// `[CODE] message` 的明细，方便用户截图定位问题。
class AppError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// 可选错误码；若传入 AppException 则优先取 code。
  final String? code;

  const AppError({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = '重试',
    this.code,
  });

  /// 直接从 AppException 构造：自动取 code + message。
  factory AppError.fromException(
    AppException exception, {
    VoidCallback? onRetry,
    String retryLabel = '重试',
  }) {
    return AppError(
      message: exception.message,
      code: exception.code,
      onRetry: onRetry,
      retryLabel: retryLabel,
    );
  }

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
              _titledMessage(),
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

  String _titledMessage() {
    final codePart = (code != null && code!.isNotEmpty) ? '[$code] ' : '';
    return '$codePart$message';
  }
}
