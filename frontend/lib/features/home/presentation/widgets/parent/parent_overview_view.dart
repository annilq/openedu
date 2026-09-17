import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/presentation/paging.dart';
import '../../../../../shared/presentation/resource.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/load_once.dart';
import '../../../../../shared/widgets/app_content_frame.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../../../children/providers/children_provider.dart';
import '../../providers/home_notifier.dart';
import '../../providers/parent_tasks_notifier.dart';
import '../../providers/selected_child_provider.dart';
import '../mastery_board.dart';

/// 家长概览右栏：学习进度 + 最近任务 + 知识点掌握度。
class ParentOverviewView extends ConsumerWidget {
  final void Function(TaskModel) onNavigateToReview;

  /// 空态出口：跳到「布置任务」页。
  final VoidCallback? onNavigateToCreate;

  const ParentOverviewView({
    super.key,
    required this.onNavigateToReview,
    this.onNavigateToCreate,
  });

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
      (s) => s is PagingIdle,
      () =>
          ref.read(parentTasksNotifierProvider.notifier).load(kAllTaskStatuses),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
      child: AppContentFrame(
        alignment: Alignment.topLeft,
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
    );
  }

  /// 未选娃娃时的引导态。
  ///
  /// 收敛到 [AppEmptyState.inline]（原先手搓 52 色块 + 单行字，与本文件里
  /// `_buildRecentTasks` 的空态是两套画法，违反 ADR-0051「三态同骨架」）。
  /// 走**安静态**：家长端工作区不该用撞色抢重量（`.impeccable.md` §Empty State）。
  Widget _emptyState(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: AppCard(
        child: AppEmptyState.inline(
          icon: LucideIcons.userRound,
          title: '还没有选娃娃',
          message: '在侧栏选一个娃娃，这里就会显示他的学习进度、最近任务和知识点掌握度。',
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context, WidgetRef ref) {
    final progState = ref.watch(progressNotifierProvider);
    final progress = progState.dataOrNull;
    return switch (progState) {
      ResourceError() => AppError(message: progState.errorOrNull ?? ''),
      _ when progress == null =>
        const AppLoading.skeletonInline(skeletonLines: 2),
      _ => PopIn(
          child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              final statWidth = wide
                  ? ((constraints.maxWidth - AppSpacing.md * 3) / 4)
                      .clamp(120.0, double.infinity)
                  : 160.0;
              return Wrap(
                runSpacing: AppSpacing.xl2,
                spacing: AppSpacing.md,
                children: [
                  _StatCard(
                      label: '总题数',
                      value: '${progress.total}',
                      cardWidth: statWidth,
                      icon: LucideIcons.listOrdered),
                  _StatCard(
                      label: '答对',
                      value: '${progress.correct}',
                      cardWidth: statWidth,
                      icon: LucideIcons.checkCircle2),
                  _StatCard(
                      label: '正确率',
                      value: '${(progress.accuracy * 100).round()}%',
                      cardWidth: statWidth,
                      icon: LucideIcons.barChart3,
                      tone: _Tone.positive),
                  _StatCard(
                      label: '连续打卡',
                      value: '${progress.streakDays}天',
                      cardWidth: statWidth,
                      icon: LucideIcons.flame,
                      tone: _Tone.warm),
                ],
              );
            },
          ),
          ),
        ),
    };
  }

  Widget _buildMastery(BuildContext context) => const MasteryBoard();

  Widget _buildRecentTasks(
      BuildContext context, WidgetRef ref, PagingState<TaskModel> tasksState) {
    if (tasksState.isLoading) {
      return const AppLoading.skeletonInline(skeletonLines: 2);
    }
    if (!tasksState.isLoaded) {
      return const SizedBox.shrink();
    }
    // 概览只看最近 4 条：分页后列表可能已有 100 条，这里必须截断，
    // 不能把整页数据都塞进概览（「最近任务」就不再是「最近」了）。
    final tasks = tasksState.items.take(4).toList();
    if (tasks.isEmpty) {
      // 内联空态 + 卡片外壳：这一栏只有约一屏的四分之一，塞 88 大色块会抢走
      // 「学习进度」的重量；但也不能只剩一行灰字——那样用户看不出这是「空」
      // 还是「加载失败」。给边界（AppCard）+ 图标 + 行动，才是完整的一句话。
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: AppCard(
          child: AppEmptyState.inline(
            icon: LucideIcons.listTodo,
            title: '还没有任务记录',
            message: '布置任务后，最近 4 条会显示在这里。',
            actionLabel: onNavigateToCreate == null ? null : '去布置任务',
            actionIcon: LucideIcons.plus,
            onAction: onNavigateToCreate,
          ),
        ),
      );
    }

    final childrenState = ref.watch(childrenNotifierProvider);
    final nameOf = _childNameResolver(childrenState);

    return Column(
      children: [
        for (int i = 0; i < tasks.length; i++)
          PopIn(
            key: ValueKey(tasks[i].id),
            child: AppCard.listRow(
              onTap: () => onNavigateToReview(tasks[i]),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: _RecentTaskRow(
                task: tasks[i],
                childName: nameOf(tasks[i].childId),
              ),
            ),
          ),
      ],
    );
  }
}

/// 概览「最近任务」单行：标题 + 状态 + 对应娃娃。
/// 卡片外壳由调用方用 [AppCard.listRow] 提供（列表降噪 + 可点）。
class _RecentTaskRow extends StatelessWidget {
  final TaskModel task;
  final String? childName;
  const _RecentTaskRow({
    required this.task,
    this.childName,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Row(
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
  final double cardWidth;
  final IconData icon;
  final _Tone tone;
  const _StatCard({
    required this.label,
    required this.value,
    required this.cardWidth,
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
    return SizedBox(
      width: cardWidth,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
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
                border: Border.all(color: AppBrutal.ink, width: 1.5),
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
      ),
    );
  }
}
