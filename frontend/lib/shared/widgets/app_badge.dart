import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 徽标视觉变体。
///
/// 先实现 [outlined]（与 assistant 旧的 `_ReadOnlyBadge` 同型）：降饱和底色 +
/// 发丝描边。其余两种先声明枚举、留作未来用例出现再实现，避免提前造出用不上的样式。
enum AppBadgeVariant { filled, outlined, subtle }

/// 小面积状态徽标（列表行 / 标签 / 题号）。
///
/// 通用化自 assistant 的 `_ReadOnlyBadge`：9 处文件散落
/// `BorderRadius.circular(AppRadius.chip)` + 相近描边 / 底色模式，统一收口到此。
///
/// 几何遵循 ADR-0044 小色块档：圆角走 [AppRadius.chip]、描边走 [AppElevation.borderWidthSm]。
/// [background] / [foreground] 缺省时按 [outlined] 取 `surfaceSunken` / `onSurfaceVariant`；
/// 其余变体的具体底色将在用例出现时实现。
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.background,
    this.foreground,
    this.variant = AppBadgeVariant.outlined,
  });

  final String label;

  /// 自定义底色；缺省随 [variant]（[outlined] 取 `surfaceSunken`）。
  final Color? background;

  /// 自定义前景（文字）色；缺省随 [variant]（[outlined] 取 `onSurfaceVariant`）。
  final Color? foreground;

  final AppBadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final bg = background ?? scheme.surfaceSunken;
    final fg = foreground ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        // 密集小色块档（chip / 徽标 / 题号），与结构边的发丝档分开（ADR-0044）。
        border: Border.all(
          color: scheme.outline,
          width: AppElevation.borderWidthSm,
        ),
      ),
      child: Text(label,
          style: text.labelSmall?.copyWith(color: fg)),
    );
  }
}
