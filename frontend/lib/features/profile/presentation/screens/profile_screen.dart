import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/theme/theme_provider.dart';
import '../../../../shared/widgets/app_dialog.dart';

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
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
                icon: LucideIcons.userRound,
                label: '用户名',
                value: user.username,
              ),
              _Divider(),
              _InfoRow(
                icon: LucideIcons.bookOpen,
                label: '角色',
                value: user.isParent ? '家长' : '学生',
              ),
              if (user.grade != null) ...[
                _Divider(),
                _InfoRow(
                  icon: LucideIcons.bookOpen,
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
          child: ShadButton(
            height: 52,
            backgroundColor: app.errorContainer,
            hoverBackgroundColor: app.errorContainer,
            pressedBackgroundColor: app.error,
            onPressed: () async {
              final confirmed = await AppDialog.confirm(
                context,
                title: Text('退出登录',
                    style: text.titleMedium?.copyWith(color: app.onSurface)),
                content: Text('确定要退出当前账号吗？',
                    style: text.bodyMedium),
                cancelLabel: '取消',
                confirmLabel: '确定退出',
                destructive: true,
              );
              if (confirmed == true) onLogout();
            },
            child: Text(
              '退出登录',
              style: text.bodyMedium?.copyWith(
                color: app.onErrorContainer,
                fontWeight: FontWeight.w600,
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
      child: Container(
        decoration: BoxDecoration(
          color: app.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _buildSegment(context, '亮色', AppThemeMode.light, mode, controller),
            _buildSegment(context, '暗色', AppThemeMode.dark, mode, controller),
            _buildSegment(context, '跟随系统', AppThemeMode.system, mode, controller),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context,
    String label,
    AppThemeMode value,
    AppThemeMode current,
    ThemeModeController controller,
  ) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final selected = current == value;
    return Expanded(
      child: ShadButton.ghost(
        height: 40,
        backgroundColor: selected ? app.primaryContainer : const Color(0x00000000),
        hoverBackgroundColor: selected
            ? app.primaryContainer
            : app.surfaceContainerHighest,
        pressedBackgroundColor: selected
            ? app.primary
            : app.surfaceContainerHighest,
        onPressed: () => controller.setMode(value),
        child: Text(
          label,
          style: text.labelSmall?.copyWith(
            color: selected ? app.onPrimaryContainer : app.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
