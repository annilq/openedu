import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../exceptions/app_exception.dart';
import '../theme/app_theme.dart';

/// 轻提示（基于 ShadToaster，替代自研 Overlay 与 Material SnackBar）。
///
/// 使用 [AppToast.show] / [AppToast.error] 在任意 context 弹出，自动消退。
/// floating 圆角扁平化，与设计系统一致。
///
/// E-Q3=a 口径：错误 Toast 若来自 AppException（含 code），展示 `[CODE] message`。
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
        // 注意：shadcn_ui 会把 offset.dx/dy 作为 EdgeInsets.symmetric 的
        // horizontal/vertical padding，必须 >= 0，否则会触发
        // `value.isNonNegative` 断言（RenderPadding.padding 不接受负值）。
        // 底部留白用 MediaQuery.paddingOf 自动扣 safeArea，dy 加 32 避免贴边。
        offset: const Offset(32, 32),
        duration: const Duration(milliseconds: 2400),
      ),
    );
  }

  /// 错误提示（温柔珊瑚）。自动带错误码前缀（E-Q3=a）。
  static void error(BuildContext context, Object err) {
    final app = AppTheme.colorsOf(context);
    final message = _format(err);

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
        offset: const Offset(32, 32),
        duration: const Duration(milliseconds: 3200),
      ),
    );
  }

  static String _format(Object err) {
    if (err is AppException) return err.titledMessage;
    if (err is Exception) return err.toString();
    return err.toString();
  }
}
