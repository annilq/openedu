import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/theme/app_theme.dart';

/// 可拖动的 AI 助手浮球锚点。
///
/// 把任意子按钮（如 [AssistantLauncher]）包进一个**自适应容器**：容器读取父级 `Stack`
/// 给到的可用区域，把按钮以 `Positioned` 钉在区域内、默认落右下角。用户可以拖动
/// 按钮到任意位置，避免它压住正文；松手后位置被持久化（按 [storageKey] 区分不同
/// 场景），下次打开仍在原处。
///
/// **交互判定（点按 / 拖动）**：指针**未发生明显移动**视为点按——交给子按钮原本的
/// `onTap`（如打开助手整页）；发生明显拖动则只移动、不再触发点按。这是外层
/// `GestureDetector` 的 pan 手势与子按钮内部的 tap 手势在竞技场里自然仲裁的结果，
/// 无需额外开关。
///
/// **坐标陷阱**：拖动时用 [DragUpdateDetails.globalPosition]（屏幕坐标系）而非相对
/// 于按钮自身的局部坐标——因为按钮自身也在跟着指针走，局部坐标会因锚点移动而
/// 失真。
class DraggableAssistantFab extends StatefulWidget {
  final Widget child;
  final String storageKey;
  final double margin;

  const DraggableAssistantFab({
    super.key,
    required this.child,
    required this.storageKey,
    this.margin = AppSpacing.lg,
  });

  @override
  State<DraggableAssistantFab> createState() => _DraggableAssistantFabState();
}

class _DraggableAssistantFabState extends State<DraggableAssistantFab> {
  Offset? _offset;
  Size? _area;
  Offset? _persisted;
  bool _dragging = false;

  Offset _panStartGlobal = Offset.zero;
  Offset _posStart = Offset.zero;
  bool _didDrag = false;

  static const double _fabSize = AppLayout.tapTargetLg;
  static const double _dragThreshold = 8.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final dx = prefs.getDouble('${widget.storageKey}_dx');
      final dy = prefs.getDouble('${widget.storageKey}_dy');
      if (dx != null && dy != null) {
        setState(() => _persisted = Offset(dx, dy));
      }
    } catch (_) {
      // 测试环境或未初始化存储时静默降级：浮球仍可用，只是不持久化。
    }
  }

  Future<void> _persist() async {
    final o = _offset;
    if (o == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('${widget.storageKey}_dx', o.dx);
      await prefs.setDouble('${widget.storageKey}_dy', o.dy);
    } catch (_) {
      // 持久化失败不影响交互。
    }
  }

  Offset _defaultOffset(Size area) {
    final p = MediaQuery.paddingOf(context);
    return Offset(
      area.width - _fabSize - widget.margin - p.right,
      area.height - _fabSize - widget.margin - p.bottom,
    );
  }

  Offset _clamp(Offset o, Size area) {
    final p = MediaQuery.paddingOf(context);
    final minX = widget.margin + p.left;
    final maxX = area.width - _fabSize - widget.margin - p.right;
    final minY = widget.margin + p.top;
    final maxY = area.height - _fabSize - widget.margin - p.bottom;
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
        _area = area;
        final offset = _clamp(
          _offset ?? _persisted ?? _defaultOffset(area),
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
                    setState(() {
                      _offset = _clamp(_posStart + delta, _area!);
                    });
                  }
                },
                onPanEnd: (_) {
                  if (mounted) setState(() => _dragging = false);
                  if (_didDrag) _persist();
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
