import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/domain/models/models.dart';
import '../../../../children/domain/providers/children_provider.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../providers/home_notifier.dart';
import '../../providers/parent_tasks_notifier.dart';
import '../../providers/selected_child_provider.dart';
import '../../../../../shared/utils/load_once.dart';
import '../mastery_board.dart';

/// 家长概览右栏：学习进度 + 最近任务 + 知识点掌握度。
class ParentOverviewView extends ConsumerWidget {
  final void Function(TaskModel) onNavigateToReview;
  const ParentOverviewView({super.key, required this.onNavigateToReview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChildProvider);
    if (selected == null) return _emptyState(context);

    // 渲染需要 watch；触发加载交给 loadWhenIdle，绝不在 build 内同步改状态。
    final tasksState = ref.watch(parentTasksNotifierProvider);

    // 进入概览即拉取最近任务（任务列表页也会复用同一份状态）。
    // 用 loadWhenIdle 而非在 build 内直接 load()：后者会同步修改被本组件 watch 的
    // provider，触发重入重建循环，使共享的 parentTasksNotifierProvider 永远停在
    // Loading，导致「最近任务」与任务列表页（共用同一 provider）一起卡转圈。
    // 规范见 docs/agents/frontend.md「Riverpod 反模式清单」。
    ref.loadWhenIdle(
      parentTasksNotifierProvider,
      (s) => s is ParentTasksIdle,
      () => ref.read(parentTasksNotifierProvider.notifier).load(),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('学习进度'),
              _buildProgress(context, ref),
              const SectionTitle('最近任务'),
              _buildRecentTasks(context, ref, tasksState),
              const SectionTitle('知识点掌握度'),
              _buildMastery(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Align(alignment: Alignment.topLeft,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.layoutDashboard,
                  size: 28, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: AppSpacing.xl),
            Text('请先在侧栏选择娃娃', style: AppTheme.textOf(context).bodyLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context, WidgetRef ref) {
    final progState = ref.watch(progressNotifierProvider);
    return switch (progState) {
      ProgressInitial() ||
      ProgressLoading() =>
        const AppLoading.skeletonInline(skeletonLines: 2),
      ProgressError() => AppError(message: progState.message),
      ProgressLoaded() => AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              return Wrap(
                runSpacing: AppSpacing.xl2,
                spacing: AppSpacing.md,
                children: [
                  _StatCard(
                      label: '总题数',
                      value: '${progState.progress.total}',
                      wide: wide,
                      icon: LucideIcons.listOrdered),
                  _StatCard(
                      label: '答对',
                      value: '${progState.progress.correct}',
                      wide: wide,
                      icon: LucideIcons.checkCircle2),
                  _StatCard(
                      label: '正确率',
                      value: '${(progState.progress.accuracy * 100).round()}%',
                      wide: wide,
                      icon: LucideIcons.barChart3,
                      tone: _Tone.positive),
                  _StatCard(
                      label: '连续打卡',
                      value: '${progState.progress.streakDays}天',
                      wide: wide,
                      icon: LucideIcons.flame,
                      tone: _Tone.warm),
                ],
              );
            },
          ),
        ),
    };
  }

  Widget _buildMastery(BuildContext context) => const MasteryBoard();

  Widget _buildRecentTasks(
      BuildContext context, WidgetRef ref, ParentTasksState tasksState) {
    if (tasksState is ParentTasksLoading) {
      return const AppLoading.skeletonInline(skeletonLines: 2);
    }
    if (tasksState is! ParentTasksLoaded) {
      return const SizedBox.shrink();
    }
    final tasks = tasksState.tasks.take(4).toList();
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text('暂无任务记录',
            style: AppTheme.textOf(context).bodySmall?.copyWith(
                  color: AppTheme.colorsOf(context).onSurfaceVariant,
                )),
      );
    }

    final childrenState = ref.watch(childrenNotifierProvider);
    final nameOf = _childNameResolver(childrenState);

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          for (int i = 0; i < tasks.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                color: AppTheme.colorsOf(context).outline,
              ),
            _RecentTaskTile(
              task: tasks[i],
              childName: nameOf(tasks[i].childId),
              onTap: () => onNavigateToReview(tasks[i]),
            ),
          ]
        ],
      ),
    );
  }
}

/// 概览「最近任务」单行：标题 + 状态 + 对应娃娃。
class _RecentTaskTile extends StatelessWidget {
  final TaskModel task;
  final String? childName;
  final VoidCallback onTap;
  const _RecentTaskTile({
    required this.task,
    this.childName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                task.title,
                style: AppTheme.textOf(context).bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (childName != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(
                  childName!,
                  style: AppTheme.textOf(context).labelSmall?.copyWith(
                        color: app.onSurfaceVariant,
                      ),
                ),
              ),
            _statusTag(task.status),
            const SizedBox(width: AppSpacing.xs),
            Icon(LucideIcons.chevronRight,
                size: 16, color: app.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _statusTag(String status) {
    switch (status) {
      case 'ready':
        return AppTags.info('待派发');
      case 'assigned':
        return AppTags.warning('进行中');
      case 'done':
        return AppTags.success('已完成');
      default:
        return AppTags.normal('草稿');
    }
  }
}

/// childId → 昵称 解析器（无匹配返回 null）。
String? Function(String?) _childNameResolver(ChildrenState state) {
  final map = <String, String>{};
  if (state is ChildrenLoaded) {
    for (final c in state.children) {
      map[c.id] = c.displayName;
    }
  }
  return (String? id) => id == null ? null : map[id];
}

// —— 私有组件 ——

enum _Tone { neutral, positive, warm, alert }

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool wide;
  final IconData icon;
  final _Tone tone;
  const _StatCard({
    required this.label,
    required this.value,
    required this.wide,
    required this.icon,
    this.tone = _Tone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final (bg, fg) = switch (tone) {
      _Tone.positive => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _Tone.warm => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _Tone.alert => (scheme.errorContainer, scheme.onErrorContainer),
      _Tone.neutral => (scheme.surfaceSunken, scheme.onSurface),
    };
    return Container(
      width: wide ? null : 160,
      constraints: wide
          ? BoxConstraints(
              minWidth: 140,
              maxWidth: (MediaQuery.of(context).size.width -
                      AppSpacing.xl2 * 2 -
                      AppSpacing.lg * 2 -
                      AppSpacing.md * 3) /
                  4,
            )
          : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: scheme.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: scheme.outline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(value,
              style: AppTheme.textOf(context).headlineMedium?.copyWith(
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: AppTheme.textOf(context).bodySmall),
        ],
      ),
    );
  }
}
