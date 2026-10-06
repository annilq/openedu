import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_focusable_action.dart';

/// 勾选框（多选列表的选中标记）。
///
/// 为什么自建：三方 checkbox（`ShadCheckbox` / Cupertino）都自带一套自己的圆角与
/// 悬停反馈，跟列表行里的 [AppTextAction] 家族不同语言；而这里是**行列表级别的
/// 多选**（资料批量删除 / 知识点批量操作），一颗 20px 的方形勾就够，要的是
/// 「和旁边的文字操作同语言」而不是一套完整表单控件。
///
/// 走 [AppFocusableAction] 而非裸手势：勾选必须能 Tab 到、能 Enter 敲选
/// （ADR-0045/0046 焦点树纪律），否则整条多选链路对键盘用户是断的。
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
    this.size = 20,
  });

  final bool selected;
  final VoidCallback? onTap;

  /// 读屏动作名。没文字标签，调用点应给出语义（如「选择两位数乘法」）。
  final String? semanticLabel;

  final double size;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return AppFocusableAction(
      onTap: onTap,
      semanticLabel: semanticLabel ?? (selected ? '取消选择' : '选择'),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? app.primary : app.surfaceRaised,
          border: Border.all(color: app.outline, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: selected
            ? Icon(LucideIcons.check, size: size - 6, color: app.onPrimary)
            : null,
      ),
    );
  }
}
