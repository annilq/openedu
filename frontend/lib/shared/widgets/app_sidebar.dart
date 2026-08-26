import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// 向侧栏子树广播收缩态 + 切换回调的 InheritedWidget。
///
/// DesktopShell 在顶层注入；AppSidebar / AppSidebarItem / _SidebarBottom
/// 通过 [of] 读取当前态并自适应。
class SidebarCollapseScope extends InheritedWidget {
  final bool collapsed;
  final VoidCallback onToggle;

  const SidebarCollapseScope({
    super.key,
    required this.collapsed,
    required this.onToggle,
    required super.child,
  });

  static SidebarCollapseScope of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SidebarCollapseScope>()!;
  }

  @override
  bool updateShouldNotify(SidebarCollapseScope old) =>
      collapsed != old.collapsed;
}

/// 侧栏导航项：图标 + 文字，active 态显示左竖条 + 浅灰药丸背景。
///
/// 收缩态（通过 [SidebarCollapseScope] 注入）只显示居中图标，
/// 隐藏 label / trailing / 左竖条，active 用药丸背景区分。
class AppSidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Widget? trailing;

  const AppSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scope = SidebarCollapseScope.of(context);
    final collapsed = scope.collapsed;
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        // 选中态即时切换，避免渐隐造成切换时的闪烁感。
        child: Container(
          padding: collapsed
              ? const EdgeInsets.symmetric(vertical: AppSpacing.sm)
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: active ? scheme.surfaceActive : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: collapsed
              ? _buildCollapsed(scheme)
              : _buildExpanded(scheme, text),
        ),
      ),
    );
  }

  Widget _buildExpanded(scheme, text) {
    return Row(
      children: [
        const SizedBox(width: AppSpacing.sm + 4),
        Icon(icon, size: 18,
            color: active ? scheme.accent : scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: active
                ? text.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  )
                : text.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }

  Widget _buildCollapsed(scheme) {
    return Center(
      child: Icon(icon, size: 20,
          color: active ? scheme.accent : scheme.onSurfaceVariant),
    );
  }
}

/// 侧栏容器：顶部区 + 收缩切换按钮 + 中部导航列表 + 底部区。
///
/// 收缩态隐藏 [top] 区；底部区由调用方根据 [SidebarCollapseScope] 自适应。
class AppSidebar extends StatelessWidget {
  final Widget? top;
  final List<Widget> items;
  final Widget? bottom;

  const AppSidebar({
    super.key,
    this.top,
    required this.items,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final scope = SidebarCollapseScope.of(context);
    return Column(
      children: [
        if (top != null && !scope.collapsed)
          Row(
            children: [
              Expanded(child: top!),
              _CollapseToggle(
                collapsed: false,
                onToggle: scope.onToggle,
              ),
            ],
          )
        else
          _CollapseToggle(
            collapsed: scope.collapsed,
            onToggle: scope.onToggle,
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: items,
          ),
        ),
        if (bottom != null) bottom!,
      ],
    );
  }
}

class _CollapseToggle extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onToggle;
  const _CollapseToggle({required this.collapsed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            collapsed
                ? LucideIcons.panelLeftOpen
                : LucideIcons.panelLeftClose,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 侧栏分隔线（细线 + padding）。收缩态退化为纯间距。
class AppSidebarDivider extends StatelessWidget {
  const AppSidebarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = SidebarCollapseScope.of(context);
    if (scope.collapsed) {
      return const SizedBox(height: AppSpacing.sm);
    }
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Container(height: 1, color: scheme.outlineVariant),
    );
  }
}
