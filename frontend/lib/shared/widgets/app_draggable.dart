import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 可拖动的浮层锚点容器（ADR-0046 手势归口）。
///
/// 把任意子控件包进一个**自适应容器**：容器读取父级给到的可用区域，把子控件以
/// `Positioned` 钉在区域内、默认落右下角。用户可把它拖到任意位置，避免压住正文。
///
/// **为什么这个手势实现在 `shared/`**：裸 `GestureDetector` 不进焦点树，业务层自建
/// 就会长出「Tab 跳不过去、Enter 点不动」的控件（ADR-0046，由 `no_bare_gesture`
/// 守卫静态拦截）。拖拽不是点按——点按语义仍由**子控件自己的** `AppIconAction` /
/// `AppFocusableAction` 承担，本容器只在它**外面**补一层位移手势，不抢焦点、不改
/// 子控件的可达性。手势实现归口 shared，业务层就没有第二处需要自己写的地方。
///
/// **交互判定（点按 / 拖动）**：指针未发生明显移动视为点按——交给子控件原本的
/// `onTap`；发生明显拖动则只移动、不再触发点按。这是外层 pan 手势与子控件内部 tap
/// 手势在竞技场里自然仲裁的结果，无需额外开关。
///
/// **坐标陷阱**：拖动时用 [DragUpdateDetails.globalPosition]（屏幕坐标系）而非相对
/// 于子控件的局部坐标——因为子控件自身也在跟着指针走，局部坐标会因锚点移动而失真。
///
/// 持久化不在本容器的职责里：松手且确实拖动过时回调 [onDragEnd]，存哪儿由调用方
/// 决定（助手浮球存 SharedPreferences，测试里可以什么都不存）。
class AppDraggable extends StatefulWidget {
  const AppDraggable({
    super.key,
    required this.child,
    required this.size,
    this.initialOffset,
    this.margin = AppSpacing.lg,
    this.onDragEnd,
  });

  final Widget child;

  /// 子控件占位边长（正方形）。用于算右下角默认位置与拖拽边界。
  final double size;

  /// 上次保存的位置（恢复用）。null = 用右下角默认位置。
  final Offset? initialOffset;

  /// 距可用区域边缘的最小间距。
  final double margin;

  /// 松手且确实拖动过 → 回传最终位置。
  final ValueChanged<Offset>? onDragEnd;

  @override
  State<AppDraggable> createState() => _AppDraggableState();
}

class _AppDraggableState extends State<AppDraggable> {
  static const double _dragThreshold = 8.0;

  Offset? _offset;
  Offset _panStartGlobal = Offset.zero;
  Offset _posStart = Offset.zero;
  bool _didDrag = false;
  bool _dragging = false;

  Offset _defaultOffset(Size area) {
    final p = MediaQuery.paddingOf(context);
    return Offset(
      area.width - widget.size - widget.margin - p.right,
      area.height - widget.size - widget.margin - p.bottom,
    );
  }

  Offset _clamp(Offset o, Size area) {
    final p = MediaQuery.paddingOf(context);
    final minX = widget.margin + p.left;
    final maxX = area.width - widget.size - widget.margin - p.right;
    final minY = widget.margin + p.top;
    final maxY = area.height - widget.size - widget.margin - p.bottom;
    // 区域过窄（如极端分屏）时避免 clamp 区间反转。
    final cx = maxX < minX ? (minX + maxX) / 2 : o.dx.clamp(minX, maxX);
    final cy = maxY < minY ? (minY + maxY) / 2 : o.dy.clamp(minY, maxY);
    return Offset(cx, cy);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        final offset = _clamp(
          _offset ?? widget.initialOffset ?? _defaultOffset(area),
          area,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: offset.dx,
              top: offset.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  _panStartGlobal = d.globalPosition;
                  _posStart = offset;
                  _didDrag = false;
                  if (mounted) setState(() => _dragging = true);
                },
                onPanUpdate: (d) {
                  final delta = d.globalPosition - _panStartGlobal;
                  if (delta.distance > _dragThreshold) _didDrag = true;
                  if (mounted) {
                    setState(() => _offset = _clamp(_posStart + delta, area));
                  }
                },
                onPanEnd: (_) {
                  if (mounted) setState(() => _dragging = false);
                  if (_didDrag) widget.onDragEnd?.call(_offset ?? offset);
                },
                child: MouseRegion(
                  cursor: _dragging
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.click,
                  child: widget.child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
