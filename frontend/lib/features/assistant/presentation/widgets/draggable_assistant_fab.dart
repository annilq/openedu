import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_draggable.dart';

/// 可拖动的 AI 助手浮球锚点。
///
/// 位移手势与布局交给 `shared/` 的 [AppDraggable]（ADR-0046：手势实现归口 shared，
/// 业务层不自建 `GestureDetector`）；本文件只负责**浮球位置的持久化**——按
/// [storageKey] 区分不同场景，下次打开仍在原处。
///
/// 点按（打开助手整页）是子按钮自己的 `onTap`，未被拖拽层抢走：位移超过阈值才算
/// 拖动，两者由手势竞技场自然仲裁。
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
  static const double _fabSize = AppLayout.tapTargetLg;

  Offset? _persisted;

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

  Future<void> _persist(Offset o) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('${widget.storageKey}_dx', o.dx);
      await prefs.setDouble('${widget.storageKey}_dy', o.dy);
    } catch (_) {
      // 持久化失败不影响交互。
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDraggable(
      size: _fabSize,
      margin: widget.margin,
      initialOffset: _persisted,
      onDragEnd: _persist,
      child: widget.child,
    );
  }
}
