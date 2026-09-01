import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../providers/home_notifier.dart';

/// 娃娃端首页：复习入口 + 今日任务列表 + 做题入口 + 打卡
/// v2 redesign：Banner 大圆角 24、Chip→AppTags、章节标题加左侧色条、
/// 空状态增加图标氛围、任务卡片 CTA 与内容间距更松。
class ChildHome extends ConsumerWidget {
  final UserModel user;
  final void Function(TaskModel task) onNavigateToPractice;
  final VoidCallback onNavigateToReview;
  final VoidCallback onNavigateToWrongQuestions;
  final VoidCallback onNavigateToTutor;

  const ChildHome({
    super.key,
    required this.user,
    required this.onNavigateToPractice,
    required this.onNavigateToReview,
    required this.onNavigateToWrongQuestions,
    required this.onNavigateToTutor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todayTasksNotifierProvider);
    final reviewState = ref.watch(dueReviewNotifierProvider);
    final dueCount =
        reviewState is DueReviewLoaded ? reviewState.items.length : 0;
    final app = AppTheme.colorsOf(context);

    return CustomScrollView(
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            await ref.read(todayTasksNotifierProvider.notifier).load();
            await ref.read(dueReviewNotifierProvider.notifier).load();
          },
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl4),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.md),
                _ReviewBanner(
                  dueCount: dueCount,
                  onReview: onNavigateToReview,
                  onWrong: onNavigateToWrongQuestions,
                ),
                PopIn(
                  duration: const Duration(milliseconds: 420),
                  child: _TutorBanner(onTutor: onNavigateToTutor),
                ),
                const SectionTitle('今日任务'),
                ...switch (state) {
                  TodayTasksInitial() || TodayTasksLoading() =>
                  const [AppLoading.skeletonInline(skeletonLines: 2)],
                  TodayTasksError() => [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: AppError(
                          message: state.message,
                          onRetry: () =>
                              ref.read(todayTasksNotifierProvider.notifier).load(),
                        ),
                      ),
                    ],
                  TodayTasksLoaded() => state.tasks.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.only(
                                top: AppSpacing.xl5,
                                left: AppSpacing.xl2,
                                right: AppSpacing.xl2),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    color: app.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(CupertinoIcons.sun_max,
                                      size: 44,
                                      color: app.onTertiaryContainer),
                                ),
                                const SizedBox(height: AppSpacing.xl2),
                                Text('今天还没有任务哦',
                                    textAlign: TextAlign.center,
                                    style: AppTheme.textOf(context).titleMedium),
                                const SizedBox(height: AppSpacing.sm),
                                Text('等爸爸妈妈布置吧～',
                                    textAlign: TextAlign.center,
                                    style: AppTheme.textOf(context).bodyMedium),
                              ],
                            ),
                          ),
                        ]
                      : state.tasks
                          .map((t) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg,
                                    vertical: AppSpacing.xs),
                                child: _TaskCard(
                                  task: t,
                                  onStart: () => onNavigateToPractice(t),
                                ),
                              ))
                          .toList(),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 复习错题横幅：更大圆角 24、图标更大、色彩更柔和——Banner 与普通卡片区分。
class _ReviewBanner extends StatelessWidget {
  final int dueCount;
  final VoidCallback onReview;
  final VoidCallback onWrong;

  const _ReviewBanner({
    required this.dueCount,
    required this.onReview,
    required this.onWrong,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: app.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.banner),
          // 顶部极细的"植物绿高光"纹理：避免完全扁平
          border: Border.all(
            color: app.primary.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: app.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(CupertinoIcons.refresh,
                    size: 32, color: app.primary),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('复习错题',
                        style: AppTheme.textOf(context).titleMedium?.copyWith(
                            color: app.onPrimaryContainer,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      dueCount > 0
                          ? '今天有 $dueCount 道题要复习'
                          : '今天没有要复习的题',
                      style: AppTheme.textOf(context).bodyMedium?.copyWith(
                          color: app.onPrimaryContainer.withValues(alpha: 0.88)),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                // 错题入口：扁平图标按钮，弱化为次要操作，突出「去复习」主按钮
                padding: const EdgeInsets.all(AppSpacing.xs),
                pressedOpacity: 0.6,
                onPressed: onWrong,
                child: Icon(CupertinoIcons.book, size: 22, color: app.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                borderRadius: const BorderRadius.all(
                    Radius.circular(AppRadius.button)),
                onPressed: onReview,
                child: const Text('去复习'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AI 老师横幅：用 secondaryContainer 的 AI 专属暖色调 + 更大圆角。
class _TutorBanner extends StatelessWidget {
  final VoidCallback onTutor;
  const _TutorBanner({required this.onTutor});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: app.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.banner),
          border: Border.all(
            color: app.secondary.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: app.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(CupertinoIcons.sparkles,
                    size: 32, color: app.secondary),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('问 AI 老师',
                        style: AppTheme.textOf(context).titleMedium?.copyWith(
                            color: app.onSecondaryContainer,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Text('遇到不懂的题，随时来问～',
                        style: AppTheme.textOf(context).bodyMedium?.copyWith(
                            color: app.onSecondaryContainer
                                .withValues(alpha: 0.88))),
                  ],
                ),
              ),
              CupertinoButton.filled(
                // AI 区主按钮沿用植物绿主色，保持单强调色一致性
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                borderRadius: const BorderRadius.all(
                    Radius.circular(AppRadius.button)),
                onPressed: onTutor,
                child: const Text('去提问'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 今日任务卡片：标签使用 AppTags.normal，"已完成"用 AppBadge.successChip
/// （避免 Colors.green 硬编码，避免芯片全都套 AI 暖黄）。
class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onStart;

  const _TaskCard({required this.task, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(task.title,
                    style: AppTheme.textOf(context).titleMedium),
              ),
              const SizedBox(width: AppSpacing.md),
              if (isDone) AppBadge.successChip('已完成'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Builder(
            builder: (context) {
              // 学科/年级/知识点已下沉到题（ADR-0004），从首题取展示值。
              final q0 = task.questions.isNotEmpty ? task.questions.first : null;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (q0 != null) ...[
                    AppTags.normal(q0.subject),
                    if (q0.grade > 0) AppTags.normal('${q0.grade}年级'),
                    AppTags.info(q0.knowledgePoint),
                  ],
                  AppTags.normal('${task.questions.length}题'),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          if (!isDone)
            AppPrimaryButton(
              label: '开始做题',
              onPressed: onStart,
            ),
        ],
      ),
    );
  }
}