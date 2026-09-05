import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../shared/domain/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_sidebar.dart';
import '../domain/providers/core_providers.dart';

/// 导航目的地（数据驱动）：同一份定义同时喂给侧栏 / 底栏 / 抽屉三种形态，
/// 避免三种布局各写一套 item，保证选中态与回调唯一来源。
class AdaptiveNavDestination {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Widget? trailing;

  const AdaptiveNavDestination({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.trailing,
  });
}

/// 响应式导航壳（ADR-0014）：按 [LayoutBuilder] 宽度在三档断点间切换布局。
///
/// - medium / expanded (≥700)：侧栏 240 ↔ 64 可收起，状态经 [StorageService] 持久化。
/// - compact (<700)：娃娃端底部导航；家长端顶部汉堡 + 左抽屉。
///
/// 侧栏/轨态复用 [AppSidebar] + [AppSidebarItem]；紧凑态自绘（不使用 Material 的
/// BottomNavigationBar / Drawer / Scaffold，因应用根基于 ShadApp 无 Material 祖先）。
class AdaptiveShell extends ConsumerStatefulWidget {
  final List<AdaptiveNavDestination> destinations;
  final Widget body;
  final AppUserMode mode;
  final Widget? sidebarTop;
  final Widget? sidebarBottom;
  final AdaptiveNavDestination? profileDestination;

  static const double expandedWidth = 240;
  static const double collapsedWidth = 64;
  static const double compactThreshold = 700;

  const AdaptiveShell({
    super.key,
    required this.destinations,
    required this.body,
    required this.mode,
    this.sidebarTop,
    this.sidebarBottom,
    this.profileDestination,
  });

  @override
  ConsumerState<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends ConsumerState<AdaptiveShell> {
  bool _collapsed = false;
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    _collapsed = ref.read(storageServiceProvider).getSidebarCollapsed();
  }

  void _toggleCollapsed() {
    setState(() => _collapsed = !_collapsed);
    ref.read(storageServiceProvider).saveSidebarCollapsed(_collapsed);
  }

  void _setDrawer(bool open) => setState(() => _drawerOpen = open);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < AdaptiveShell.compactThreshold;

        if (isCompact) {
          return widget.mode == AppUserMode.child
              ? _buildCompactBottomNav(context)
              : _buildCompactDrawer(context);
        }

        // 中 / 大屏：侧栏 240 ↔ 64 可收起；收起偏好对所有非紧凑宽度生效并持久化。
        final railWidth =
            _collapsed ? AdaptiveShell.collapsedWidth : AdaptiveShell.expandedWidth;
        final scheme = AppTheme.colorsOf(context);
        return SidebarCollapseScope(
          collapsed: _collapsed,
          onToggle: _toggleCollapsed,
        child: Row(
          // 内容页贴顶自然布局，绝不垂直居中（避免内容少的页面上下留白「局中」）。
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: railWidth,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  border: Border(
                    right: BorderSide(color: scheme.outline, width: 1),
                  ),
                ),
                child: ClipRect(
                  child: AppSidebar(
                    top: widget.sidebarTop,
                    items: widget.destinations
                        .map((d) => AppSidebarItem(
                              icon: d.icon,
                              label: d.label,
                              active: d.active,
                              onTap: d.onTap,
                              trailing: d.trailing,
                            ))
                        .toList(),
                    bottom: widget.sidebarBottom,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  color: scheme.surface,
                  child: widget.body,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- 紧凑·娃娃端：底部导航 ----
  Widget _buildCompactBottomNav(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final items = [...widget.destinations];
    if (widget.profileDestination != null) items.add(widget.profileDestination!);
    return Column(
      children: [
        Expanded(
          child: Container(
            color: scheme.surface,
            child: widget.body,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            border: Border(top: BorderSide(color: scheme.outline, width: 1)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: items
                    .map((d) => _BottomNavItem(destination: d))
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- 紧凑·家长端：顶部汉堡 + 左抽屉 ----
  Widget _buildCompactDrawer(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final items = [...widget.destinations];
    if (widget.profileDestination != null) items.add(widget.profileDestination!);
    return Stack(
      children: [
        Column(
          children: [
            _CompactTopBar(onMenu: () => _setDrawer(true)),
            Expanded(
              child: Container(
                color: scheme.surface,
                child: widget.body,
              ),
            ),
          ],
        ),
        if (_drawerOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _setDrawer(false),
              child: Container(color: scheme.scrim),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          left: _drawerOpen ? 0 : -AdaptiveShell.expandedWidth,
          top: 0,
          bottom: 0,
          width: AdaptiveShell.expandedWidth,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border(right: BorderSide(color: scheme.outline, width: 1)),
            ),
            child: Column(
              children: [
                if (widget.sidebarTop != null) widget.sidebarTop!,
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm),
                    children: items
                        .map((d) => _DrawerItem(destination: d))
                        .toList(),
                  ),
                ),
                if (widget.sidebarBottom != null) widget.sidebarBottom!,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 底部导航项（紧凑·娃娃端）。等宽分布，选中态用 accent。
class _BottomNavItem extends StatelessWidget {
  final AdaptiveNavDestination destination;
  const _BottomNavItem({required this.destination});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final color = destination.active ? scheme.accent : scheme.onSurfaceVariant;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: destination.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(destination.icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                destination.label,
                style: AppTheme.textOf(context).labelSmall?.copyWith(
                      color: color,
                      fontWeight:
                          destination.active ? FontWeight.w600 : FontWeight.w500,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 抽屉导航项（紧凑·家长端）。图标 + 文字 + 选中药丸。
class _DrawerItem extends StatelessWidget {
  final AdaptiveNavDestination destination;
  const _DrawerItem({required this.destination});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: destination.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 2),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: destination.active
                ? scheme.surfaceActive
                : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            children: [
              Icon(destination.icon, size: 18,
                  color: destination.active
                      ? scheme.accent
                      : scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  destination.label,
                  style: text.labelLarge?.copyWith(
                    color: destination.active
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight:
                        destination.active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (destination.trailing != null) destination.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// 紧凑·家长端顶部条：汉堡按钮 + 应用名。
class _CompactTopBar extends StatelessWidget {
  final VoidCallback onMenu;
  const _CompactTopBar({required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: scheme.outline, width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMenu,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(LucideIcons.menu,
                    size: 20, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('娃娃学习',
              style: AppTheme.textOf(context).titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
        ],
      ),
    );
  }
}

/// 导航壳底部用户区（侧栏 / 轨 / 抽屉共用）。
///
/// 收缩态（通过 [SidebarCollapseScope] 注入；抽屉内无 scope 视为展开）只显示头像，
/// 展开态显示头像 + 名称 + 副标题（年级 / 家长账号）+ 进入箭头。
class AdaptiveUserBlock extends StatelessWidget {
  final UserModel user;
  final VoidCallback onProfileTap;
  final String? subtitle;

  const AdaptiveUserBlock({
    super.key,
    required this.user,
    required this.onProfileTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final scope =
        context.dependOnInheritedWidgetOfExactType<SidebarCollapseScope>();
    final collapsed = scope?.collapsed ?? false;
    final name = user.displayName;
    final sub = subtitle ?? '家长账号';

    if (collapsed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outline, width: 1)),
        ),
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onProfileTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AvatarSquircle.small(name: name),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onProfileTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outline, width: 1)),
          ),
          child: Row(
            children: [
              AvatarSquircle.small(name: name),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppTheme.textOf(context).labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                    Text(sub,
                        style: AppTheme.textOf(context).labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            )),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight,
                  size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
