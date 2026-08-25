import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_motion.dart';

/// 做题结果弹窗：复用 [AppDialog.alert]，内部按 [correct] 渲染 36x36 图标容器
/// （tertiary + check / error + refreshCw），两屏一致。
///
/// 差异由调用方传入：[title] 文案、[content] 内容 Widget、[animateIcon] 是否套
/// [PopIn] 入场动画（practice 用，review 不用）。
class AppAnswerResultDialog {
  AppAnswerResultDialog._();

  static Future<void> show(
    BuildContext context, {
    required bool correct,
    required String title,
    required Widget content,
    bool animateIcon = false,
  }) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final iconContainer = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: correct ? scheme.tertiaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        correct ? LucideIcons.check : LucideIcons.refreshCw,
        size: 22,
        color: correct ? scheme.onTertiaryContainer : scheme.onErrorContainer,
      ),
    );
    final titleRow = Row(
      children: [
        animateIcon
            ? PopIn(
                fromScale: 0.72,
                duration: const Duration(milliseconds: 360),
                child: iconContainer,
              )
            : iconContainer,
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            title,
            style: text.titleMedium?.copyWith(
              color: correct
                  ? scheme.onTertiaryContainer
                  : scheme.onErrorContainer,
            ),
          ),
        ),
      ],
    );
    return AppDialog.alert(context, title: titleRow, content: content);
  }
}
