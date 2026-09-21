import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Squircle 方圆形头像。
class AvatarSquircle extends StatelessWidget {
  final String name;
  final double size;
  final Color? bg;
  final Color? fg;

  const AvatarSquircle({
    super.key,
    required this.name,
    this.size = 96,
    this.bg,
    this.fg,
  });

  const AvatarSquircle.small({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 40;

  /// 紧凑预设：用于侧栏/顶栏的触发芯片（如切换娃娃按钮），比 [small] 更小。
  const AvatarSquircle.xs({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 28;

  const AvatarSquircle.medium({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 56;

  const AvatarSquircle.large({
    super.key,
    required this.name,
    this.bg,
    this.fg,
  }) : size = 80;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final background = bg ?? app.primaryContainer;
    final foreground = fg ?? app.onPrimaryContainer;
    return ShadAvatar(
      null,
      size: Size.square(size),
      backgroundColor: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(size * 0.32)),
        side: BorderSide.none,
      ),
      placeholder: Text(
        name.isNotEmpty ? name[0] : '?',
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontFamilyFallback: AppTheme.fontFamilyFallback,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
