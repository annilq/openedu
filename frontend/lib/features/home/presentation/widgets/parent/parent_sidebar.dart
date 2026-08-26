import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_sidebar.dart';
import 'parent_child_selector.dart';

/// 家长端侧栏：顶部娃娃选择器 + 5 项导航 + 底部"家长"用户菜单。
///
/// 导航项 0-4 切换右栏内容；"娃娃管理"与"我的资料"收敛在底部用户区，
/// 点击底部用户块弹出子菜单选择。
class ParentSidebar extends StatelessWidget {
  final UserModel user;
  final int selectedIndex;
  final ValueChanged<int> onNavTap;
  final VoidCallback onProfileTap;
  final VoidCallback? onNavigateToAddChild;

  const ParentSidebar({
    super.key,
    required this.user,
    required this.selectedIndex,
    required this.onNavTap,
    required this.onProfileTap,
    this.onNavigateToAddChild,
  });

  @override
  Widget build(BuildContext context) {
    return AppSidebar(
      top: ParentChildSelector(onNavigateToAddChild: onNavigateToAddChild),
      items: [
        AppSidebarItem(
          icon: LucideIcons.layoutDashboard,
          label: '概览',
          active: selectedIndex == 0,
          onTap: () => onNavTap(0),
        ),
        AppSidebarItem(
          icon: LucideIcons.pencil,
          label: '布置任务',
          active: selectedIndex == 1,
          onTap: () => onNavTap(1),
        ),
        AppSidebarItem(
          icon: LucideIcons.bookOpen,
          label: '错题本',
          active: selectedIndex == 2,
          onTap: () => onNavTap(2),
        ),
        AppSidebarItem(
          icon: LucideIcons.sparkles,
          label: 'AI 答疑记录',
          active: selectedIndex == 3,
          onTap: () => onNavTap(3),
        ),
        AppSidebarItem(
          icon: LucideIcons.shieldCheck,
          label: 'AI 管控',
          active: selectedIndex == 4,
          onTap: () => onNavTap(4),
        ),
      ],
      bottom: _SidebarBottom(user: user, onProfileTap: onProfileTap),
    );
  }
}

/// 底部"家长"用户区：点击直接进入个人资料页。
class _SidebarBottom extends StatelessWidget {
  final UserModel user;
  final VoidCallback onProfileTap;
  const _SidebarBottom({required this.user, required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final collapsed = SidebarCollapseScope.of(context).collapsed;

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
            child: AvatarSquircle.small(name: user.displayName),
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
            border: Border(
              top: BorderSide(color: scheme.outline, width: 1),
            ),
          ),
          child: Row(
            children: [
              AvatarSquircle.small(name: user.displayName),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName,
                        style: AppTheme.textOf(context).labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                    Text('家长账号',
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
