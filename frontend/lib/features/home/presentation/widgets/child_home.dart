import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
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
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerLow,
      onRefresh: () async {
        await ref.read(todayTasksNotifierProvider.notifier).load();
        await ref.read(dueReviewNotifierProvider.notifier).load();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl4),
        children: [
          const SizedBox(height: AppSpacing.md),
          _ReviewBanner(
            dueCount: dueCount,
            onReview: onNavigateToReview,
            onWrong: onNavigateToWrongQuestions,
          ),
          _TutorBanner(onTutor: onNavigateToTutor),
          SectionTitle('今日任务'),
          ...switch (state) {
            TodayTasksInitial() || TodayTasksLoading() =>
              const [Padding(padding: EdgeInsets.all(AppSpacing.xl5), child: AppLoading(message: '加载今日任务...'))],
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
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.wb_sunny_outlined,
                                size: 44,
                                color: scheme.onTertiaryContainer),
                          ),
                          const SizedBox(height: AppSpacing.xl2),
                          Text('今天还没有任务哦',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: AppSpacing.sm),
                          Text('等爸爸妈妈布置吧～',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.banner),
          // 顶部极细的"植物绿高光"纹理：避免完全扁平
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.18),
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
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.autorenew_rounded,
                    size: 32, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('复习错题',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      dueCount > 0
                          ? '今天有 $dueCount 道题要复习'
                          : '今天没有要复习的题',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer.withValues(alpha: 0.88)),
                    ),
                  ],
                ),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerLow,
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                        color: scheme.outline,
                        width: 1),
                  ),
                ),
                onPressed: onWrong,
                icon: const Icon(Icons.menu_book_rounded, size: 24),
                tooltip: '错题本',
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.banner),
          border: Border.all(
            color: scheme.secondary.withValues(alpha: 0.18),
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
                  color: scheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.smart_toy_rounded,
                    size: 32, color: scheme.secondary),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('问 AI 老师',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Text('遇到不懂的题，随时来问～',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSecondaryContainer
                                .withValues(alpha: 0.88))),
                  ],
                ),
              ),
              FilledButton(
                // AI 区主按钮沿用植物绿主色，保持单强调色一致性
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(task.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(width: AppSpacing.md),
                if (isDone) AppBadge.successChip('已完成'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppTags.normal(task.subject),
                AppTags.normal('${task.grade}年级'),
                AppTags.info(task.knowledgePoint),
                AppTags.normal('${task.questions.length}题'),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            if (!isDone)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onStart,
                  child: const Text('开始做题'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
