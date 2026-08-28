import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../providers/home_notifier.dart';

/// 娃娃端首页：复习入口 + 今日任务列表 + 做题入口 + 打卡。
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

    return RefreshIndicator(
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
                            child: Icon(LucideIcons.sun,
                                size: 44, color: app.onTertiaryContainer),
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
                              horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
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
    final app = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: app.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.banner),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: app.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(LucideIcons.refreshCw,
                    size: 32, color: app.onPrimary),
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
                          color: app.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              ShadButton.ghost(
                onPressed: onWrong,
                child: Icon(LucideIcons.bookOpen, size: 22, color: app.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              ShadButton(
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
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: app.secondary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(LucideIcons.sparkles,
                    size: 32, color: app.onSecondary),
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
                            color: app.onSecondaryContainer)),
                  ],
                ),
              ),
              ShadButton(
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

/// 今日任务卡片：标签用 AppTags.normal，"已完成"用 AppBadge.successChip。
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
          Builder(builder: (_) {
            // ADR-0004：Task 学科下沉到题，按题集汇总显示。
            final subjects =
                task.questions.map((q) => q.subject).where((s) => s.isNotEmpty).toSet().toList();
            final firstQ =
                task.questions.isNotEmpty ? task.questions.first : null;
            final subjectLabel = subjects.length > 1
                ? '多科（${subjects.length}）'
                : (subjects.isNotEmpty ? subjects.first : '');
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (subjectLabel.isNotEmpty) AppTags.normal(subjectLabel),
                if (firstQ != null && firstQ.grade > 0)
                  AppTags.normal('${firstQ.grade}年级'),
                if (subjects.length == 1 && firstQ != null && firstQ.knowledgePoint.isNotEmpty)
                  AppTags.info(firstQ.knowledgePoint),
                AppTags.normal('${task.questions.length}题'),
              ],
            );
          }),
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