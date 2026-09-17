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
                // 「连续打卡」是这一栏唯一的焦点（hero）：撞色底 + 硬阴影 + 最大字号；
                // 其余三个数字降为安静行（无卡片壳、无彩色块），把重量让给焦点。
                // 四张等大等重、三张还是中性灰的卡片等于没有主次——用户扫一眼不知道
                // 该看哪个（`.impeccable.md`「色块是强调件，不是背景纸」）。
                final hero = _StreakHero(days: progress.streakDays);
                final quiet = _QuietStats(
                  total: progress.total,
                  correct: progress.correct,
                  accuracy: progress.accuracy,
                );

                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      hero,
                      const SizedBox(height: AppSpacing.md),
                      quiet,
                    ],
                  );
                }
                // ⚠️ Row(stretch) 必须包 IntrinsicHeight：本 Row 落在高度无界的
                // LayoutBuilder 里，否则抛 `BoxConstraints forces an infinite height`
                // （守卫 test/stretch_row_guard_test.dart）。
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: hero),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(flex: 3, child: quiet),
                    ],
                  ),
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

/// 焦点指标：连续打卡。撞色底 + 硬阴影 + 全屏最大字号，是这一栏唯一被强调的数字。
///
/// **为什么是打卡而不是正确率**：正确率是结果指标，天天盯着会焦虑；打卡是连续行为，
/// 对娃娃是游戏化、对家长是动力——是家长端情绪目标「一眼看清、有掌控感、不焦虑」
/// 下唯一适合被庆祝的指标。
///
/// ⚠️ 字号取 [AppText.displayLarge]，即现有类型阶梯的**顶格**（22px）。
/// 本仓 `AppText._typeScale` 的区间只有 12–22px，所以 `bolder` 那条「3–5× 阶差」
/// 在现有令牌下**物理上做不到**（22 / 13 ≈ 1.7×）。真要做大字焦点需给 `_typeScale`
/// 新增一档展示字号——那是设计系统单一事实源的改动，应先记 ADR，不在本次范围。
/// 这里靠**撞色底 + 硬阴影 + 字重 w800** 补足对比度。
class _StreakHero extends StatelessWidget {
  final int days;

  const _StreakHero({required this.days});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    // 撞色底只能配 [AppBrutal.onColor]，不得手写黑/白（.impeccable.md 原则 3）。
    // orange 是亮块 → onColor 返回墨黑（实测 7.61:1）。选它是因为「火焰 / 连续」
    // 的暖色语义，且学科色板只占用 blue / coral / yellow，与它不冲突。
    const fill = AppBrutal.orange;
    final fg = AppBrutal.onColor(fill);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppBrutal.ink,
          width: AppElevation.borderWidth,
        ),
        boxShadow: AppElevation.hard(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.flame, size: 20, color: fg),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '连续打卡',
                style: text.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$days',
                style: text.displayLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppSpacing.xs2),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('天', style: text.titleSmall?.copyWith(color: fg)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 安静指标组：焦点之外的三个数字。
///
/// 去卡片壳、去彩色块，只留「图标 + 标签 + 数字」三行——它们是**陪衬**，不再是
/// 三个与 hero 等重的方块。原先总题数 / 答对 / 正确率走 `_Tone.neutral` 落到
/// `surfaceSunken`，在白卡上几乎看不见（正是 `MEMORY.md` 记的「白物体在纸底
/// 没边界」同族问题）。
class _QuietStats extends StatelessWidget {
  final int total;
  final int correct;
  final double accuracy;

  const _QuietStats({
    required this.total,
    required this.correct,
    required this.accuracy,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Icon(icon, size: 16, color: app.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                ),
              ),
              Text(
                value,
                style: text.titleMedium?.copyWith(
                  color: app.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        row(LucideIcons.listOrdered, '总题数', '$total'),
        row(LucideIcons.checkCircle2, '答对', '$correct'),
        row(LucideIcons.barChart3, '正确率', '${(accuracy * 100).round()}%'),
      ],
    );
  }
}
