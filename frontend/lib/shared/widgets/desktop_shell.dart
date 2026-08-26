import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/providers/core_providers.dart';
import '../theme/app_theme.dart';
import 'app_sidebar.dart';

/// 桌面左右分栏壳：左侧可收缩侧栏 + 右侧自适应内容区。
///
/// 侧栏宽度：展开 240 / 收起 64，带 280ms easeOutCubic 动画。
/// 收缩态持久化到 SharedPreferences。
class DesktopShell extends ConsumerStatefulWidget {
  final Widget sidebar;
  final Widget body;

  static const double expandedWidth = 240;
  static const double collapsedWidth = 64;

  const DesktopShell({
    super.key,
    required this.sidebar,
    required this.body,
  });

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _collapsed = ref.read(storageServiceProvider).getSidebarCollapsed();
  }

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    ref.read(storageServiceProvider).saveSidebarCollapsed(_collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return SidebarCollapseScope(
      collapsed: _collapsed,
      onToggle: _toggle,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: _collapsed
                ? DesktopShell.collapsedWidth
                : DesktopShell.expandedWidth,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border(
                right: BorderSide(color: scheme.outline, width: 1),
              ),
            ),
            child: ClipRect(child: widget.sidebar),
          ),
          Expanded(
            child: Container(
              // 与卡片一致的纯白底，避免内容区发灰、短页大块露灰显"居中"
              color: scheme.surfaceContainerLow,
              child: widget.body,
            ),
          ),
        ],
      ),
    );
  }
}
