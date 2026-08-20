import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/home_notifier.dart';

/// 娃娃端首页：今日任务列表 + 做题入口 + 打卡
class ChildHome extends ConsumerWidget {
  final UserModel user;
  final void Function(TaskModel task) onNavigateToPractice;

  const ChildHome({
    super.key,
    required this.user,
    required this.onNavigateToPractice,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todayTasksNotifierProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(todayTasksNotifierProvider.notifier).load(),
      child: switch (state) {
        TodayTasksInitial() || TodayTasksLoading() =>
          const AppLoading(message: '加载今日任务...'),
        TodayTasksError() => AppError(
            message: state.message,
            onRetry: () => ref.read(todayTasksNotifierProvider.notifier).load(),
          ),
        TodayTasksLoaded() => state.tasks.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text('今天还没有任务哦\n等爸爸妈妈布置吧～',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20)),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: state.tasks.length,
                itemBuilder: (ctx, i) {
                  final task = state.tasks[i];
                  return _TaskCard(
                    task: task,
                    onStart: () => onNavigateToPractice(task),
                  );
                },
              ),
      },
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
