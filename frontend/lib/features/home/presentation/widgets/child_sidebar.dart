import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_sidebar.dart';

/// 娃娃端侧栏：4 项导航 + 底部用户区。
///
/// 导航项 0-3 切换右栏内容。
/// 底部用户区点击后右栏显示 ProfileScreen（替代原"我的"入口）。
class ChildSidebar extends StatelessWidget {
  final UserModel user;
  final int selectedIndex;
  final ValueChanged<int> onNavTap;
  final VoidCallback onProfileTap;

  const ChildSidebar({
    super.key,
    required this.user,
    required this.selectedIndex,
    required this.onNavTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppSidebar(
      items: [
        AppSidebarItem(
          icon: LucideIcons.house,
          label: '首页',
          active: selectedIndex == 0,
          onTap: () => onNavTap(0),
        ),
        AppSidebarItem(
          icon: LucideIcons.refreshCw,
          label: '复习',
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
          label: 'AI 伴学',
          active: selectedIndex == 3,
          onTap: () => onNavTap(3),
        ),
      ],
      bottom: _SidebarBottom(user: user, onProfileTap: onProfileTap),
    );
  }
}

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
          border: Border(
            top: BorderSide(color: scheme.outline, width: 1),
          ),
        ),
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onProfileTap,
          child: AvatarSquircle.small(name: user.displayName),
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
                    Text('${user.grade ?? '?'}年级',
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
