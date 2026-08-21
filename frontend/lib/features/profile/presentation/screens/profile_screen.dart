import 'package:flutter/material.dart';
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
    final theme = Theme.of(context);
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
            style: theme.textTheme.headlineSmall?.copyWith(
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.person_outline,
                label: '用户名',
                value: user.username,
              ),
              _Divider(),
              _InfoRow(
                icon: Icons.school_outlined,
                label: '角色',
                value: user.isParent ? '家长' : '学生',
              ),
              if (user.grade != null) ...[
                _Divider(),
                _InfoRow(
                  icon: Icons.grade_outlined,
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
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  title: const Text('退出登录'),
                  content: const Text('确定要退出当前账号吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onLogout();
                      },
                      child: const Text('确定退出'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('退出登录'),
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
    final theme = Theme.of(context);
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
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// 外观设置：亮色 / 暗色 / 跟随系统（持久化）。
class _ThemeModeSetting extends ConsumerWidget {
  const _ThemeModeSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final controller = ref.read(themeModeProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('亮色'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('暗色'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('跟随系统'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) =>
                controller.setMode(selection.first),
            showSelectedIcon: false,
          ),
        ],
      ),
    );
  }
}
