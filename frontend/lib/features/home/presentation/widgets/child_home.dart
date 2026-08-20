import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../providers/home_notifier.dart';

/// 娃娃端首页：复习入口 + 今日任务列表 + 做题入口 + 打卡
class ChildHome extends ConsumerWidget {
  final UserModel user;
  final void Function(TaskModel task) onNavigateToPractice;
  final VoidCallback onNavigateToReview;
  final VoidCallback onNavigateToWrongQuestions;

  const ChildHome({
    super.key,
    required this.user,
    required this.onNavigateToPractice,
    required this.onNavigateToReview,
    required this.onNavigateToWrongQuestions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todayTasksNotifierProvider);
    final reviewState = ref.watch(dueReviewNotifierProvider);
    final dueCount =
        reviewState is DueReviewLoaded ? reviewState.items.length : 0;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(todayTasksNotifierProvider.notifier).load();
        await ref.read(dueReviewNotifierProvider.notifier).load();
      },
      child: ListView(
        children: [
          _ReviewBanner(
            dueCount: dueCount,
            onReview: onNavigateToReview,
            onWrong: onNavigateToWrongQuestions,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('今日任务', style: Theme.of(context).textTheme.titleMedium),
          ),
          ...switch (state) {
            TodayTasksInitial() || TodayTasksLoading() =>
              const [Padding(padding: EdgeInsets.all(48), child: AppLoading(message: '加载今日任务...'))],
            TodayTasksError() => [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppError(
                    message: state.message,
                    onRetry: () =>
                        ref.read(todayTasksNotifierProvider.notifier).load(),
                  ),
                ),
              ],
            TodayTasksLoaded() => state.tasks.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(
                        child: Text('今天还没有任务哦\n等爸爸妈妈布置吧～',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ]
                : state.tasks
                    .map((t) => _TaskCard(
                          task: t,
                          onStart: () => onNavigateToPractice(t),
                        ))
                    .toList(),
          },
        ],
      ),
    );
  }
}

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
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.autorenew, size: 40, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('复习错题',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                  const SizedBox(height: 4),
                  Text(
                    dueCount > 0 ? '今天有 $dueCount 道题要复习' : '今天没有要复习的题',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onWrong,
              icon: const Icon(Icons.menu_book),
              tooltip: '错题本',
            ),
            FilledButton(
              onPressed: onReview,
              child: const Text('去复习'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onStart;

  const _TaskCard({required this.task, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(task.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (isDone)
                  const Chip(
                    label: Text('已完成'),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(task.subject)),
                Chip(label: Text('年级 ${task.grade}')),
                Chip(label: Text(task.knowledgePoint)),
                Chip(label: Text('${task.questions.length}题')),
              ],
            ),
            const SizedBox(height: 16),
            if (!isDone)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
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
