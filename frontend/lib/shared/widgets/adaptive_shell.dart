import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../shared/domain/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_sidebar.dart';
import '../domain/providers/core_providers.dart';
import 'app_content_frame.dart';
import 'app_avatar.dart';
import 'app_focusable_action.dart';

/// 底部用户区在展开态需要的最小可用宽度：低于此值按 collapsed（仅头像）渲染，
/// 复用与导航项同样的兜底逻辑，规避折叠/展开动画途中展开行（头像 + 间距 +
/// 进入箭头 = 64px 固定）被塞进窄容器导致的横向溢出。取 100 ≈ 头像 40 + 间距 8 +
/// 箭头 16 的余量；低于此宽必然放不下展开行。
const double _kUserBlockExpandedMinWidth = 100;

/// 抽屉左滑关闭的位移阈值：抽屉宽度的四分之一。
///
/// 从 [AppLayout.sidebarExpanded] 推导而不是写裸数字——抽屉宽度改了阈值自动跟随，
/// 不会出现「抽屉变窄了却仍要滑 60px 才关」。
const double _drawerDismissDragThreshold = AppLayout.sidebarExpanded / 4;

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

/// 响应式导航壳（ADR-0014 / ADR-0045）：按 [LayoutBuilder] 的**可用宽度**分三档。
///
/// | 可用宽度 | 布局 |
/// |---|---|
/// | `< [AppLayout.compactMax]`（紧凑） | 学生端底部导航；教师端顶部汉堡 + 左抽屉 |
/// | `[compactMax, largeMin)`（中屏） | 侧栏 240 ↔ 64 可收起 |
/// | `≥ [AppLayout.largeMin]`（大屏） | 同上 |
///
/// 另（ADR-0045）：内容区统一套 [AppLayout.contentWide] 宽度上限并居中——大屏下
/// 防止文本行过长、卡片被无限拉宽。页面若需更窄（登录 480 / 答题 820），自带
/// 更强的 [ConstrainedBox] 即可，内层更紧者生效。
///
/// 侧栏/轨态复用 [AppSidebar] + [AppSidebarItem]；紧凑态自绘（不使用 Material 的
/// BottomNavigationBar / Drawer / Scaffold，因应用根基于 ShadApp 无 Material 祖先）。
class AdaptiveShell extends ConsumerStatefulWidget {
  final List<AdaptiveNavDestination> destinations;
  final Widget body;

  /// [body] 是唯一的页面宿主：曾经还有个 [detail] 覆盖层（master-detail，
  /// `detail ?? body`），已在 ADR-0059 移除——它让「当前该看哪个页面」变成两个
  /// 状态的优先级裁决，而裁决散落在各个导航回调里，漏清一个就整幅顶替掉 body。
  /// 现在壳只认一个 body，页面互斥由调用方的单一导航状态保证。

  final AppUserMode mode;
  final Widget? sidebarTop;
  final Widget? sidebarBottom;
  final AdaptiveNavDestination? profileDestination;

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
        final isCompact = width < AppLayout.compactMax;

        if (isCompact) {
          return widget.mode == AppUserMode.student
              ? _buildCompactBottomNav(context)
              : _buildCompactDrawer(context);
        }

        // 中 / 大屏：侧栏 240 ↔ 64 可收起；收起偏好对所有非紧凑宽度生效并持久化。
        final railWidth =
            _collapsed ? AppLayout.sidebarCollapsed : AppLayout.sidebarExpanded;
        final scheme = AppTheme.colorsOf(context);
        return SidebarCollapseScope(
          collapsed: _collapsed,
          onToggle: _toggleCollapsed,
          child: Row(
            // 内容页贴顶自然布局，绝不垂直居中（避免内容少的页面上下留白「局中」）。
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                // 隐式动画须显式尊重 reduce-motion（ADR-0044）。
                duration: reducedMotionOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                width: railWidth,
                decoration: BoxDecoration(
                  color: scheme.surfaceSunken,
                  border: Border(
                    right: BorderSide(
                      color: scheme.outline,
                      width: AppElevation.borderWidthHairline,
                    ),
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
                  child: _cappedWidth(widget.body),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 内容宽度上限 + 水平居中：大屏下避免文本行过长、卡片被无限拉宽。
  ///
  /// 壳只用 [AppContentFrame]（ADR-0045 的唯一出口），各pages 也用同一个组件，
  /// 免得 width token 散在十几处各写一份。
  ///
  /// 为什么是 `topCenter` 而**不是** [Center]：这里只想约束横向。`Center` 的竖向
  /// 居中会让「内容不足一屏」的页面（表单、错误态）整块浮到屏幕中间——本仓刻意要
  /// 「内容贴顶自然布局」。`Align` 横向传下松约束，贪心子项（ListView / scroll view）
  /// 仍会取满 `contentWide`，与 `Center` 等效。
  ///
  /// 紧凑宽度下 1080 不生效，等价于无包裹（不改变手机 / 小平板的现有排布）。
  Widget _cappedWidth(Widget child) => AppContentFrame(
        child: child,
      );

  // ---- 紧凑·学生端：底部导航 ----
  Widget _buildCompactBottomNav(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final items = [...widget.destinations];
    if (widget.profileDestination != null) items.add(widget.profileDestination!);
    return Column(
      children: [
        Expanded(
          child: Container(
            color: scheme.surface,
            child: _cappedWidth(widget.body),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceSunken,
            border: Border(top: BorderSide(color: scheme.outline, width: AppElevation.borderWidthHairline)),
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

  // ---- 紧凑·教师端：顶部汉堡 + 左抽屉 ----
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
                child: _cappedWidth(widget.body),
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
          // 隐式动画须显式尊重 reduce-motion（ADR-0044）。
          duration: reducedMotionOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          left: _drawerOpen ? 0 : -AppLayout.sidebarExpanded,
          top: 0,
          bottom: 0,
          width: AppLayout.sidebarExpanded,
          child: _DrawerSwipeToDismiss(
            enabled: _drawerOpen,
            onDismiss: () => _setDrawer(false),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceSunken,
                border: Border(
                    right: BorderSide(
                        color: scheme.outline,
                        width: AppElevation.borderWidthHairline)),
              ),
              child: Column(
              children: [
                // 抽屉无收缩按钮，但仍要给同一份头部内边距——否则 sidebarTop
                // 会贴边，与下面缩进 8px 的抽屉项对不上（左右两条边缘）。
                if (widget.sidebarTop != null)
                  Padding(
                    padding: AppLayout.sidebarHeaderPadding,
                    child: widget.sidebarTop!,
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm),
                    children: items
                        .map((d) => _DrawerItem(
                              destination: d,
                              // 关闭必须发生在导航**之后**：先让目标页进渲染树，
                              // 再收抽屉，避免动画途中抽屉与内容同时重排。
                              onTap: () {
                                d.onTap?.call();
                                _setDrawer(false);
                              },
                            ))
                        .toList(),
                  ),
                ),
                if (widget.sidebarBottom != null) widget.sidebarBottom!,
              ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 抽屉面板的左滑关闭手势。
///
/// 纯手势补充：抽屉项仍然是 [AppFocusableAction]，桌面端 Tab 依旧跳得过去
/// （ADR-0046）——手势只多给移动端一条出路，不接替可点区域。
///
/// 位移阈值取抽屉宽度的四分之一（[_drawerDismissDragThreshold]）：比手指的一次
/// 拖拽短（好关），比列表竖向滚动的横向抖动长（不误触）。收起动画沿用
/// [AnimatedPositioned] 的同一档时长，因此也一并尊重 reduce-motion。
class _DrawerSwipeToDismiss extends StatefulWidget {
  final bool enabled;
  final VoidCallback onDismiss;
  final Widget child;

  const _DrawerSwipeToDismiss({
    required this.enabled,
    required this.onDismiss,
    required this.child,
  });

  @override
  State<_DrawerSwipeToDismiss> createState() => _DrawerSwipeToDismissState();
}

class _DrawerSwipeToDismissState extends State<_DrawerSwipeToDismiss> {
  /// 本次拖拽累计的横向位移（左为负）。必须是 State：拖拽途中 `onDismiss`
  /// 会触发壳的 setState 重建本组件，Stateless 会让位移在重建时清零。
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: widget.enabled
          ? (details) {
              // 只累加左滑：向右拽是把抽屉拽回来，而它已经在最左端。
              if (details.delta.dx < 0) _drag += details.delta.dx;
            }
          : null,
      onHorizontalDragEnd: widget.enabled
          ? (_) {
              final dismissed = _drag <= -_drawerDismissDragThreshold;
              _drag = 0;
              if (dismissed) widget.onDismiss();
            }
          : null,
      child: widget.child,
    );
  }
}

/// 底部导航项（紧凑·学生端）。等宽分布，选中态用 accent。
class _BottomNavItem extends StatelessWidget {
  final AdaptiveNavDestination destination;
  const _BottomNavItem({required this.destination});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final color = destination.active ? scheme.accent : scheme.onSurfaceVariant;
    return Expanded(
      child: AppFocusableAction(
        onTap: destination.onTap,
        semanticLabel: destination.label,
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
    );
  }
}

/// 抽屉导航项（紧凑·教师端）。图标 + 文字 + 选中药丸。
class _DrawerItem extends StatelessWidget {
  final AdaptiveNavDestination destination;

  /// 抽屉项的完整动作：导航（[AdaptiveNavDestination.onTap]）+ 收起抽屉。
  /// 由壳注入，因为「当前抽屉是否打开」是壳的状态。
  final VoidCallback onTap;

  const _DrawerItem({required this.destination, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      // margin 提到焦点环外侧：环必须贴着药丸，而不是把 margin 也圈进去。
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      child: AppFocusableAction(
        onTap: onTap,
        semanticLabel: destination.label,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        hoverHighlight: true,
        child: Container(
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

/// 紧凑·教师端顶部条：汉堡按钮 + 应用名。
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
        color: scheme.surfaceSunken,
        border: Border(bottom: BorderSide(color: scheme.outline, width: AppElevation.borderWidthHairline)),
      ),
      child: Row(
        children: [
          AppFocusableAction(
            onTap: onMenu,
            semanticLabel: '打开导航菜单',
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: SizedBox(
              width: AppLayout.tapTarget,
              height: AppLayout.tapTarget,
              child: Icon(LucideIcons.menu,
                  size: 20, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('学生学习',
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
/// 展开态显示头像 + 名称 + 副标题（年级 / 教师账号）+ 进入箭头。
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
    final name = user.displayName;
    final sub = subtitle ?? '教师账号';

    return LayoutBuilder(
      builder: (context, constraints) {
        // 同 AppSidebarItem：collapsed 布尔量瞬间翻转，而宽度是连续动画的，
        // 动画途中若按展开态渲染，头像行会被塞进窄容器 → 横向溢出。
        final collapsed = (scope?.collapsed ?? false) ||
            constraints.maxWidth < _kUserBlockExpandedMinWidth;
        if (collapsed) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: scheme.outline,
                  width: AppElevation.borderWidthHairline,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: AppFocusableAction(
              onTap: onProfileTap,
              semanticLabel: '$name · $sub',
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: AvatarSquircle.small(name: name),
            ),
          );
        }

        return AppFocusableAction(
      onTap: onProfileTap,
      semanticLabel: '$name · $sub',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outline,
              width: AppElevation.borderWidthHairline,
            ),
          ),
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
        );
      },
    );
  }
}
