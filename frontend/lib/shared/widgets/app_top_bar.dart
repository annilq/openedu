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

  /// 自定义返回行为。覆盖层场景（未走 Navigator.push）必须提供，否则
  /// 默认 [Navigator.maybePop] 因无可 pop 路由而失效。为 null 时走默认 pop。
  final VoidCallback? onBack;

  const AppTopBar({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.showBack = false,
    this.onBack,
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
      onPressed: () =>
          onBack != null ? onBack!() : Navigator.of(context).maybePop(),
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
