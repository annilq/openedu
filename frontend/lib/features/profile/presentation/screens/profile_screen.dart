import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/theme/theme_provider.dart';

class ProfileScreen extends ConsumerWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final roleTag = user.isParent
        ? AppTags.normal('家长账号')
        : AppTags.info('${user.grade ?? "?"}年级');

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Header: avatar + name + role
        Center(
          child: AvatarSquircle.large(
            name: user.displayName.isNotEmpty ? user.displayName : '?',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            user.displayName,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(child: roleTag),
        if (!user.isParent) ...[
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              '@${user.username}',
              style: text.bodyMedium?.copyWith(
                color: app.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),

        // 外观：亮暗主题切换
        const SectionTitle('外观'),
        const SizedBox(height: AppSpacing.sm),
        _ThemeModeSetting(),

        const SizedBox(height: AppSpacing.xxl),

        // Info card
        const SectionTitle('账号信息'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: app.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: app.outlineVariant,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              _InfoRow(
                icon: CupertinoIcons.person,
                label: '用户名',
                value: user.username,
              ),
              _Divider(),
              _InfoRow(
                icon: CupertinoIcons.book,
                label: '角色',
                value: user.isParent ? '家长' : '学生',
              ),
              if (user.grade != null) ...[
                _Divider(),
                _InfoRow(
                  icon: CupertinoIcons.book,
                  label: '年级',
                  value: '${user.grade}年级',
                ),
              ],
            ],
          ),
        ),

        SizedBox(height: AppSpacing.xxl),

        // Logout
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: app.errorContainer,
            disabledColor: app.errorContainer,
            borderRadius: BorderRadius.circular(AppRadius.button),
            padding: const EdgeInsets.symmetric(vertical: 16),
            onPressed: () {
              showCupertinoDialog(
                context: context,
                builder: (ctx) => CupertinoAlertDialog(
                  title: const Text('退出登录'),
                  content: const Text('确定要退出当前账号吗？'),
                  actions: [
                    CupertinoDialogAction(
                      isDefaultAction: true,
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    CupertinoDialogAction(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onLogout();
                      },
                      textStyle: TextStyle(
                        color: app.error,
                        fontWeight: FontWeight.w600,
                      ),
                      child: const Text('确定退出'),
                    ),
                  ],
                ),
              );
            },
            child: Text(
              '退出登录',
              style: TextStyle(
                color: app.onErrorContainer,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: app.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            label,
            style: text.bodyLarge?.copyWith(
              color: app.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: text.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: app.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        height: 1,
        color: app.outlineVariant,
      ),
    );
  }
}

/// 外观设置：亮色 / 暗色 / 跟随系统（持久化）。
class _ThemeModeSetting extends ConsumerWidget {
  const _ThemeModeSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = AppTheme.colorsOf(context);
    final mode = ref.watch(themeModeProvider);
    final controller = ref.read(themeModeProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: app.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: app.outlineVariant,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoSlidingSegmentedControl<AppThemeMode>(
            groupValue: mode,
            onValueChanged: (v) {
              if (v != null) controller.setMode(v);
            },
            backgroundColor: app.surfaceContainerHigh,
            thumbColor: app.primaryContainer,
            children: {
              AppThemeMode.light:
                  _segLabel(context, '亮色', mode == AppThemeMode.light),
              AppThemeMode.dark:
                  _segLabel(context, '暗色', mode == AppThemeMode.dark),
              AppThemeMode.system:
                  _segLabel(context, '跟随系统', mode == AppThemeMode.system),
            },
          ),
        ],
      ),
    );
  }
}

/// 分段控件的标签：显式指定选中/未选中颜色，避免被 Cupertino 默认蓝覆盖。
Widget _segLabel(BuildContext context, String label, bool selected) {
  final app = AppTheme.colorsOf(context);
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Text(
      label,
      style: TextStyle(
        color: selected ? app.onPrimaryContainer : app.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    ),
  );
}