import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// 轻提示（基于 ShadToaster，替代自研 Overlay 与 Material SnackBar）。
///
/// 使用 [AppToast.show] / [AppToast.error] 在任意 context 弹出，自动消退。
/// floating 圆角扁平化，与设计系统一致。
class AppToast {
  AppToast._();

  /// 普通提示。
  static void show(BuildContext context, String message) {
    final app = AppTheme.colorsOf(context);
    final isDark = app.brightness == Brightness.dark;
    final bg = isDark ? app.surfaceContainerHigh : const Color(0xFF2F2A24);
    final fg = isDark ? app.onSurface : app.surfaceContainerLowest;

    ShadToaster.of(context).show(
      ShadToast(
        description: Text(
          message,
          style: AppTheme.textOf(context).bodyMedium?.copyWith(
                color: fg,
                height: 1.3,
              ),
        ),
        backgroundColor: bg,
        closeIconData: LucideIcons.x,
        alignment: Alignment.bottomCenter,
        offset: const Offset(0, -24),
        duration: const Duration(milliseconds: 2400),
      ),
    );
  }

  /// 错误提示（温柔珊瑚）。
  static void error(BuildContext context, String message) {
    final app = AppTheme.colorsOf(context);

    ShadToaster.of(context).show(
      ShadToast.destructive(
        description: Text(
          message,
          style: AppTheme.textOf(context).bodyMedium?.copyWith(
                color: app.onError,
                height: 1.3,
              ),
        ),
        backgroundColor: app.error,
        closeIconData: LucideIcons.x,
        alignment: Alignment.bottomCenter,
        offset: const Offset(0, -24),
        duration: const Duration(milliseconds: 2400),
      ),
    );
  }
}
