import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// 顶部导航栏：替代 [CupertinoNavigationBar]。
///
/// 设计：无描边、surfaceRaised 背景、52 高度、Leading/Trailing 40 宽槽位
/// 平衡标题居中。默认 `showBack=true` 时自带 Lucide chevronLeft 返回按钮。
class AppTopBar extends StatelessWidget {
  final String title;
  final Widget? leading;
  final Widget? trailing;
  final bool showBack;

  const AppTopBar({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final defaultLeading = ShadButton.ghost(
      width: 40,
      height: 40,
      padding: EdgeInsets.zero,
      backgroundColor: const Color(0x00000000),
      hoverBackgroundColor: app.surfaceSunken,
      pressedBackgroundColor: app.surfaceRaised,
      onPressed: () => Navigator.of(context).maybePop(),
      child: Icon(
        LucideIcons.chevronLeft,
        color: app.onSurface,
        size: 24,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: app.surfaceRaised,
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: leading ?? (showBack ? defaultLeading : const SizedBox.shrink()),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: text.titleMedium,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: trailing ?? const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
