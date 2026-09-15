import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// 向侧栏子树广播收缩态 + 切换回调的 InheritedWidget。
///
/// AdaptiveShell 在侧栏 / 收起轨态注入；AppSidebar / AppSidebarItem 通过 [of]
/// 读取当前态并自适应（抽屉态无 scope，组件按展开态渲染）。
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

  /// 可空版本：抽屉态不注入本 scope，`sidebarTop` 仍会被渲染。
  ///
  /// 读不到的语义是「没有可收缩的侧栏」→ 视为展开态（抽屉本来就是全宽面板）。
  static SidebarCollapseScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SidebarCollapseScope>();
  }

  @override
  bool updateShouldNotify(SidebarCollapseScope old) =>
      collapsed != old.collapsed;
}

/// 侧栏导航项：图标 + 文字，active 态用药丸底色 + accent 图标。
///
/// 收缩态（通过 [SidebarCollapseScope] 注入）只显示居中图标，
/// 隐藏 label 与 trailing，active 仍靠药丸底色区分。
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

    return Padding(
      // margin 提到焦点环外侧：环必须贴着药丸，而不是把 margin 也圈进去。
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 2),
      child: AppFocusableAction(
        onTap: onTap,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        hoverHighlight: true,
        child: Container(
          padding: collapsed
              ? const EdgeInsets.symmetric(vertical: AppSpacing.sm)
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: active ? scheme.surfaceActive : CupertinoColors.transparent,
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

/// 侧栏容器：头部区（可选 [top] + 收缩切换按钮）+ 中部导航列表 + 底部区。
///
/// 头部四向内边距统一走 [AppLayout.sidebarHeaderPadding]，使 [top] 的左缘与导航项
/// 左缘对齐；展开时 [top] 与收缩按钮同行（按钮贴右），收起时二者竖排堆叠，保证
/// 「当前在看谁的数据」这一信息在轨态不丢失。
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
        _buildHeader(context, scope),
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

  /// 头部：只有 [top] 为空时才退化为「单独一个居中切换按钮」。
  Widget _buildHeader(BuildContext context, SidebarCollapseScope scope) {
    final toggle = _CollapseToggle(
      collapsed: scope.collapsed,
      onToggle: scope.onToggle,
    );
    if (top == null) {
      return Padding(
        padding: AppLayout.sidebarHeaderPadding,
        child: Align(alignment: Alignment.center, child: toggle),
      );
    }
    return Padding(
      padding: AppLayout.sidebarHeaderPadding,
      child: scope.collapsed
          ? Column(
              children: [
                top!,
                const SizedBox(height: AppSpacing.xs),
                toggle,
              ],
            )
          : Row(
              children: [
                Expanded(child: top!),
                const SizedBox(width: AppSpacing.sm),
                toggle,
              ],
            ),
    );
  }
}

/// 侧栏收起 / 展开按钮。
///
/// 悬停底色走 [AppFocusableAction.hoverHighlight]（与导航项同一套悬停语言）；
/// 尺寸取 [AppLayout.tapTarget]，与头部另一侧的选择器同高，基线齐平。
class _CollapseToggle extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onToggle;
  const _CollapseToggle({required this.collapsed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppFocusableAction(
      onTap: onToggle,
      semanticLabel: collapsed ? '展开侧栏' : '收起侧栏',
      borderRadius: BorderRadius.circular(AppRadius.chip),
      hoverHighlight: true,
      child: SizedBox(
        width: AppLayout.tapTarget,
        height: AppLayout.tapTarget,
        child: Icon(
          collapsed ? LucideIcons.panelLeftOpen : LucideIcons.panelLeftClose,
          size: 18,
          color: scheme.onSurfaceVariant,
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
      child: Container(
        height: AppElevation.borderWidthHairline,
        color: scheme.outline,
      ),
    );
  }
}
