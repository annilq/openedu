import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// 通用对话框（基于 ShadDialog，替代 showCupertinoDialog / CupertinoAlertDialog）。
///
/// 两种模式：
/// - [AppDialog.alert]：单按钮结果提示（做题结果等）。
/// - [AppDialog.confirm]：取消/确认双按钮确认弹窗（退出登录等）。
class AppDialog {
  AppDialog._();

  /// 结果提示弹窗：标题 + 正文 + 单按钮关闭。
  static Future<void> alert(
    BuildContext context, {
    Widget? title,
    Widget? content,
    String confirmLabel = '继续',
  }) async {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    await showShadDialog(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => ShadDialog(
        closeIcon: const SizedBox.shrink(),
        title: title,
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              confirmLabel,
              style: text.labelMedium?.copyWith(color: app.onPrimary),
            ),
          ),
        ],
        child: content,
      ),
    );
  }

  /// 确认弹窗：标题 + 正文 + 取消/确认按钮，返回是否确认。
  static Future<bool?> confirm(
    BuildContext context, {
    Widget? title,
    Widget? content,
    String cancelLabel = '取消',
    String confirmLabel = '确定',
    bool destructive = false,
  }) async {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return showShadDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => ShadDialog(
        closeIcon: const SizedBox.shrink(),
        title: title,
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              cancelLabel,
              style: text.labelMedium?.copyWith(color: app.onSurface),
            ),
          ),
          ShadButton(
            backgroundColor: destructive ? app.error : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              confirmLabel,
              style: text.labelMedium?.copyWith(
                color: destructive ? app.onError : app.onPrimary,
              ),
            ),
          ),
        ],
        child: content,
      ),
    );
  }
}
