import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_focusable_action.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

/// 卡片：2px 墨黑描边 + 硬阴影（新粗野），可点击时按下整卡位移、阴影收拢。
///
/// 卡片强度变体（ADR-0044「列表降噪」）。
/// - [standard]：2px 墨黑描边 + 硬阴影，用于独立卡片 / 强调件。
/// - [listRow]：1px 墨黑描边 + 无阴影，用于密集列表的逐行卡片——避免每行
///   都压 2px 边 + 硬阴影导致家长端看板视觉过载（「统一到家长端上限」的代价补偿）。
///
/// ⚠️ **卡片比内容高时，内容会贴顶、不会垂直居中**：底层 [ShadCard] 内部固定是
/// `Row(crossAxisAlignment: start)` → `Column(mainAxisSize: min)`，内容只按自身高度
/// 收缩并朝上沿对齐。内容自撑高度时（绝大多数用法）两者相等、看不出问题；一旦外面用
/// `SizedBox(height:)` 把卡片钉高（如侧栏头部触发器），差值就变成底部一段空白。
/// 调用点需自己包一层 `Center`——不要指望这里居中，改这里会动到全站每张卡片的布局。
enum AppCardVariant { standard, listRow }

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double? radius;
  final Border? border;
  final VoidCallback? onTap;
  final AppCardVariant variant;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.color,
    this.radius,
    this.border,
    this.onTap,
    this.variant = AppCardVariant.standard,
  });

  /// 密集列表逐行卡片：1px 墨黑边、无阴影。
  const AppCard.listRow({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.color,
    this.radius,
    this.border,
    this.onTap,
  }) : variant = AppCardVariant.listRow;

  static ShadBorder _convertBorder(Border b) {
    ShadBorderSide side(BorderSide s) => ShadBorderSide(
          color: s.color,
          width: s.width,
          style: s.style,
        );
    return ShadBorder(
      top: side(b.top),
      right: side(b.right),
      bottom: side(b.bottom),
      left: side(b.left),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    // 暗模式下墨黑硬阴影与描边同色、不可见 → 退化为无阴影（ADR-0044）。
    List<BoxShadow> shadowsFor(bool pressed) => app.brightness == Brightness.dark
        ? AppElevation.none
        : (pressed
            ? AppElevation.hardPressed(app.outline)
            : AppElevation.hard(app.outline));

    // 列表行变体：发丝边、无阴影；标准变体：2px 边 + 硬阴影。
    final isRow = variant == AppCardVariant.listRow;
    final borderWidth =
        isRow ? AppElevation.borderWidthHairline : AppElevation.borderWidth;
    final rowShadows = AppElevation.none;

    ShadCard buildCard(Color borderColor, List<BoxShadow> shadows) => ShadCard(
          padding: padding,
          backgroundColor: color ?? app.surfaceContainerLow,
          radius: BorderRadius.circular(radius ?? AppRadius.card),
          border: border != null
              ? _convertBorder(border!)
              : ShadBorder.all(color: borderColor, width: borderWidth),
          shadows: shadows,
          child: child,
        );
    // NOTE: Do NOT wrap `buildCard(...)` in `ShadButton.ghost(width: double.infinity)`.
    // That injects a `BoxConstraints(minWidth: ∞, maxWidth: ∞)` into the card,
    // which shadcn's internal `ShadCard` structure
    // (`Row(mainAxisSize: min) → Flexible → Column → Flexible → child`) then
    // passes down as UNBOUNDED width. Any `Expanded`/`Flexible` inside the
    // card content (e.g. the task-list card's `Row(Expanded)`) then throws
    // "RenderFlex children have non-zero flex but incoming width constraints
    // are unbounded". A bare `GestureDetector` is pass-through: it imposes no
    // width constraint, so the card receives the parent's bounded width and
    // still fills it via its own `Expanded` content. `GestureDetector` needs
    // no `Material` ancestor, so it is safe under `ShadApp`.
    if (onTap == null) {
      return Container(
          margin: margin,
          child: buildCard(app.outline, isRow ? rowShadows : shadowsFor(false)));
    }
    // 可点击卡片：hover 时边框微深到 outlineHover，让"可点"有真实反馈；
    // 按下时整卡下沉 + 阴影收拢（新粗野的「按压」语义，ADR-0044）。
    // (hover, pressed) 打包进同一个 notifier，避免两层 ValueListenableBuilder。
    final state = ValueNotifier<(bool, bool)>((false, false));
    return Container(
      margin: margin,
      child: ValueListenableBuilder<(bool, bool)>(
        valueListenable: state,
        builder: (_, s, __) {
          final (h, p) = s;
          return MouseRegion(
            cursor: SystemMouseCursors.basic,
            onEnter: (_) => state.value = (true, state.value.$2),
            onExit: (_) => state.value = (false, state.value.$2),
            // 走 AppFocusableAction（而非裸 GestureDetector）：卡片是全站最主要的可点
            // 区域，裸 GestureDetector 不在焦点树里 → 桌面端 Tab 得到菜单却打不开任何东西
            // （ADR-0045）。它全程不注入宽高约束，因此不会踩上面 ShadButton.ghost 那个
            // 「无界宽度」的坑；键盘 Enter/Space 也会走同一 onTap。
            child: AppFocusableAction(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius ?? AppRadius.card),
              onPressedChanged: (pressed) =>
                  state.value = (state.value.$1, pressed),
              // 只动 transform（GPU 合成），不触发布局重排。
              child: Transform.translate(
                offset: p ? AppElevation.offsetPressed : Offset.zero,
              child: buildCard(h ? app.outlineHover : app.outline,
                  isRow ? rowShadows : shadowsFor(p)),
              ),
            ),
          );
        },
      ),
    );
  }
}
