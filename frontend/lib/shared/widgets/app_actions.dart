import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_focusable_action.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

/// 行内图标操作：方形命中区 + 居中图标，尺寸走 [AppControl] 标准档。
///
/// 为什么需要它：`CupertinoButton(padding: EdgeInsets.zero, child: Icon(...))`
/// 看着是「纯图标」，实际被 Cupertino 的默认 `minSize` 钉成 **44×44**——与标准档
/// 输入框同行时会把整行撑高 4px，且图标中心与输入框文字中线错位。这是本仓第三种
/// 「控件高度权威」（前两种是 [AppControl] 与 `ShadButton` 的内容盒高，见
/// [AppControl.buttonContentHeight]），必须收口。
///
/// 命中区取标准档而非更小的紧凑档：行高本就由同行的输入框决定，命中区与行高对齐
/// 既不会撑行，也不牺牲可点性（紧凑档 32 在密集表单里偏小）。
///
/// **不是裸 `GestureDetector`**：内层走 [AppFocusableAction]，因此进焦点树、支持
/// Enter / Space 激活、有焦点环与悬停底色。`CupertinoButton` 本来是可聚焦的，
/// 直接换成裸手势会**倒退键盘可达性**（见 ADR-0046）。
class AppIconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  /// 图标视觉尺寸（命中区恒为标准档，与此无关）。
  final double iconSize;
  final Color? color;

  /// 读屏动作名。图标按钮没有文字，**调用点应尽量提供**（如「删除该选项」）。
  final String? semanticLabel;

  const AppIconAction({
    super.key,
    required this.icon,
    this.onPressed,
    this.iconSize = 18,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final hit = AppControl.heightOf(context);
    final tint = onPressed != null
        ? (color ?? app.onSurfaceVariant)
        : app.onSurfaceVariant.withValues(alpha: 0.5);
    return AppFocusableAction(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      hoverHighlight: true,
      child: SizedBox(
        width: hit,
        height: hit,
        child: Center(child: Icon(icon, size: iconSize, color: tint)),
      ),
    );
  }
}

/// 行内文字操作：用于卡片 / 列表行里的「编辑 / 删除 / 设为默认」等二次动作。
///
/// 与 [AppIconAction] 同属「行内操作」家族：方形命中区换成文字标签 + 水平内边距，
/// 其余属性（焦点树 / 悬停药丸 / 键盘 Enter 激活）完全一致。
///
/// 为什么不用 `CupertinoButton`：它会把 child 套进 Cupertino 主题的
/// `DefaultTextStyle`，强制使用系统字体（.SF Pro / PingFang），**覆盖**
/// 我们内嵌的 Inter + Noto Sans SC；中文会变糙、字号也会跳到 Cupertino 默认值。
/// 这里显式给 `Text` 传 `AppTheme.textOf` 样式，保证字形与字号都走设计系统。
class AppTextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// 文字色。不传时走 `onSurfaceVariant`；删除等破坏动作用 `app.error`。
  final Color? color;

  /// 读屏动作名。文字标签本身可读时通常无需再传。
  final String? semanticLabel;

  const AppTextAction({
    super.key,
    required this.label,
    this.onPressed,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final tint = onPressed != null
        ? (color ?? app.onSurfaceVariant)
        : app.onSurfaceVariant.withValues(alpha: 0.5);
    final child = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        label,
        style: text.labelMedium?.copyWith(color: tint),
      ),
    );
    return AppFocusableAction(
      onTap: onPressed,
      semanticLabel: semanticLabel ?? label,
      hoverHighlight: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: AppControl.heightSmOf(context),
        ),
        child: Center(
          widthFactor: 1,
          child: child,
        ),
      ),
    );
  }
}
