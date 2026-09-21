import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

/// 主操作按钮：品牌靛蓝 CTA（走 accent）。
/// 主行动按钮（品牌蓝 CTA）。
///
/// [height] 是**可见总高**（含 2px 描边），默认走标准档 [AppControl.heightOf]；
/// 单屏唯一的主行动传 [AppControl.heightLgOf]。内部会换算成 shadcn 需要的内容盒
/// 高度——这一点很关键：`ShadButton.height` 并非可见高度，直接透传会让按钮比同行
/// 的输入框高出 2×描边宽。
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;
  final IconData? icon;
  final String? loadingLabel;

  /// 可见总高；null 走标准档。
  final double? height;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.fullWidth = true,
    this.icon,
    this.loadingLabel,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final spinner = Icon(
      LucideIcons.loaderCircle,
      size: 18,
      color: app.onCta,
    ).animate(onPlay: (c) => c.repeat()).rotate(
          begin: 0,
          end: 1,
          duration: const Duration(milliseconds: 900),
          curve: Curves.linear,
        );
    final labelWidget = Text(
      loading ? (loadingLabel ?? label) : label,
      textAlign: TextAlign.center,
      style: AppTheme.textOf(context).labelLarge?.copyWith(
            color: app.onCta,
          ),
    );
    final child = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading ? spinner : Icon(icon, size: 16, color: app.onCta),
              const SizedBox(width: 8),
              labelWidget,
            ],
          )
        : (loading ? spinner : labelWidget);
    return ShadButton(
      // 令牌给的是可见总高，ShadButton 要的是内容盒高 → 减掉 2×描边宽。
      height: AppControl.buttonContentHeight(
        height ?? AppControl.heightOf(context),
      ),
      expands: fullWidth,
      onPressed: loading ? null : onPressed,
      child: child,
    );
  }
}

/// 新粗野实心按钮：撞色填充 + 唯一合规前景 + 2px 墨黑描边 + 硬阴影，
/// 按下时整块下沉（[AppElevation.offsetPressed]）并收拢阴影（ADR-0044）。
///
/// 与 [AppPrimaryButton] 的区别：后者走 shadcn 主题（品牌蓝 CTA），本组件
/// 接受任意 [AppBrutal] 撞色，用于「每屏最多 3 个色相」的强调件。
///
/// 前景色**不**由调用方传——必须走 [AppBrutal.onColor]，否则亮块配白字会
/// 掉到 4.78:1 以下（实测所有高饱和色配白字最高仅 4.78）。
class AppBrutalButton extends StatefulWidget {
  final String label;
  final Color fill;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;

  /// 可见总高；null 走标准档 [AppControl.heightOf]。
  ///
  /// 与 [AppPrimaryButton] 的 `height` 语义**一致**（都是可见总高）：本组件用裸
  /// `Container` + `BoxDecoration(border:)`，Flutter 的描边画在盒内，故传入值
  /// 就是可见高度，无需换算。
  final double? height;

  const AppBrutalButton({
    super.key,
    required this.label,
    required this.fill,
    this.onPressed,
    this.icon,
    this.fullWidth = false,
    this.height,
  });

  @override
  State<AppBrutalButton> createState() => _AppBrutalButtonState();
}

class _AppBrutalButtonState extends State<AppBrutalButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (widget.onPressed == null) return;
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final enabled = widget.onPressed != null;
    final fg = AppBrutal.onColor(widget.fill);
    final content = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onPressed,
      child: Opacity(
        // 禁用态沿用全站 disabledOpacity 语义，不新增令牌。
        opacity: enabled ? 1 : 0.5,
        child: Transform.translate(
          // 只动 transform（GPU 合成）；下沉是即时位移而非补间动画，
          // 因此无需按 reduce-motion 关闭（手势与反馈都保留）。
          offset: _pressed ? AppElevation.offsetPressed : Offset.zero,
          child: Container(
            height: widget.height ?? AppControl.heightOf(context),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.fill,
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadius.button)),
              border: Border.all(
                color: AppBrutal.ink,
                width: AppElevation.borderWidth,
              ),
              boxShadow: _pressed
                  ? AppElevation.hardPressed()
                  : AppElevation.hard(),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
