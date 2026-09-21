import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

/// 键盘可达的即时点击区（ADR-0045）。
///
/// **背景**：本仓的可点区域（导航项 / 列表行 / 卡片）一律用裸 [GestureDetector] +
/// `MouseRegion` 实现（应用根是 `ShadApp`、无 Material 祖先，因此刻意不用 `InkWell`）。
/// 但裸 [GestureDetector] **不进焦点树**——Tab 跳不过去、Enter/Space 也点不动，桌面端
/// 因此完全没有键盘可达性；`flutter analyze` 也照不出这类问题（它不是类型错误）。
///
/// 本组件补齐三件事：
/// 1. 进入焦点树（[FocusableActionDetector] + `Shortcuts`/`Actions`）；
/// 2. `Enter` / `Space` / 小键盘回车激活——与鼠标点击走**同一个** [onTap]；
/// 3. 焦点可见：聚焦时叠一圈 2px 焦点环（不使用系统默认高亮）。
///
/// 用 `foregroundDecoration` 而非 `decoration` 画焦点环：前者覆盖绘制、**不参与布局**，
/// 因此聚焦 / 失焦不会让元素尺寸跳动（描边加粗导致行高变化的经典坑）。
///
/// 焦点环取 [AppColors.accent]（靛蓝）而非墨黑：本仓的墨黑描边到处都是（卡片、列表行、
/// 每组色块的边），用墨黑画焦点环会退化成「边框好像变粗了」，读不出「焦点在这里」。
///
/// **约束**：本组件全程不注入任何宽高约束（`FocusableActionDetector` / `Semantics` /
/// `GestureDetector` / `MouseRegion` / `DecoratedBox` 都是透传的 proxy），因此可以安全地
/// 包住 [AppCard]——那张卡对「外层塞进无界宽度」极其敏感（见上方 `ShadButton.ghost`
/// 的 NOTE）。
///
/// [onTap] 为空或 [enabled] 为 false 时不进焦点树——不可操作的项不该被 Tab 到。
class AppFocusableAction extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// 按压态变化（按下 → true，抬起 / 取消 → false）。
  ///
  /// 用于驱动「整卡下沉」「硬阴影收拢」这类按压反馈：键盘 [ActivateIntent] 也会
  /// 走一次 true→false，使键盘激活与鼠标点击有同样的视觉反馈。
  final ValueChanged<bool>? onPressedChanged;

  /// 焦点环圆角；缺省跟随 chip 档（与导航药丸一致）。
  final BorderRadius? borderRadius;

  final bool enabled;

  /// 供读屏使用的动作名（如「首页」）。
  final String? semanticLabel;

  /// 悬停时是否垫一层药丸底色（缺省否）。
  ///
  /// 只画底色，**不改布局**（与焦点环同思路）。底部绘制，故选中的子项自带底色时
  /// 会盖住它——「选中」与「悬停」因而天然分层：悬停是浅的 `surfaceHover`，选中是
  /// 深的 `surfaceActive`，同一元素上二者可区分。
  ///
  /// 侧栏导航项 / 收缩按钮 / 下拉菜单项这类「无文字撑宽、只有图标或短标签」的可点
  /// 区域都应打开；否则鼠标移上去没有任何反馈（触屏看不出来，桌面端很明显）。
  final bool hoverHighlight;

  const AppFocusableAction({
    super.key,
    required this.child,
    this.onTap,
    this.onPressedChanged,
    this.borderRadius,
    this.enabled = true,
    this.semanticLabel,
    this.hoverHighlight = false,
  });

  @override
  State<AppFocusableAction> createState() => _AppFocusableActionState();
}

class _AppFocusableActionState extends State<AppFocusableAction> {
  bool _focused = false;
  bool _hovered = false;

  bool get _actionable => widget.enabled && widget.onTap != null;

  void _activate() {
    // 键盘激活补齐一次按压反馈：鼠标走 onTapDown/Up，键盘两者都没有。
    widget.onPressedChanged?.call(true);
    widget.onPressedChanged?.call(false);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.chip);
    return FocusableActionDetector(
      enabled: _actionable,
      includeFocusSemantics: true,
      onShowFocusHighlight: (v) {
        if (_focused != v) setState(() => _focused = v);
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: _actionable,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              _actionable ? (_) => widget.onPressedChanged?.call(true) : null,
          onTapUp: _actionable
              ? (_) => widget.onPressedChanged?.call(false)
              : null,
          onTapCancel:
              _actionable ? () => widget.onPressedChanged?.call(false) : null,
          onTap: _actionable ? _activate : null,
          child: MouseRegion(
            cursor: _actionable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: widget.hoverHighlight
                ? (_) => setState(() => _hovered = true)
                : null,
            onExit: widget.hoverHighlight
                ? (_) => setState(() => _hovered = false)
                : null,
            child: DecoratedBox(
              // 悬停底色画在**底层**（decoration），子项自带的选中底色会盖住它。
              decoration: BoxDecoration(
                color: _hovered && _actionable
                    ? scheme.surfaceHover
                    : CupertinoColors.transparent,
                borderRadius: radius,
              ),
              // 焦点环画在顶层（foregroundDecoration）：覆盖绘制、不参与布局，
              // 因此聚焦 / 失焦不会让元素尺寸跳动（描边加粗导致行高变化的经典坑）。
              child: Container(
                foregroundDecoration: _focused && _actionable
                    ? BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: scheme.accent,
                          width: AppElevation.borderWidth,
                        ),
                      )
                    : null,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
