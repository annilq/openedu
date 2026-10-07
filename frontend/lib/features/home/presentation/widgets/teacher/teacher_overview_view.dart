import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/presentation/paging.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/load_once.dart';
import '../../../../../shared/widgets/app_scroll_page.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_section_title.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/presentation/shell_navigation.dart';
import '../../../../students/presentation/providers/students_notifier.dart';
import '../../../../students/providers/students_provider.dart';
import '../../providers/teacher_tasks_notifier.dart';
import '../../providers/task_form_prefill.dart';
import '../../providers/teacher_overview_provider.dart';

/// 教师概览（整体视角）：班级掌握度概览 + 薄弱知识点 + 最近任务。
///
/// 不再绑定单个学生（原先依赖全局 [selectedStudentProvider]），改为读取教师整体聚合
/// [teacherOverviewProvider]。与「学情统计」分工：本页是进入即看的速览，
/// 统计页是带作用域 / 维度下钻的深入分析，二者不重叠。
class TeacherOverviewView extends ConsumerWidget {
  final void Function(TaskModel) onNavigateToReview;

  /// 空态出口：跳到「布置任务」页。
  final VoidCallback? onNavigateToCreate;

  const TeacherOverviewView({
    super.key,
    required this.onNavigateToReview,
    this.onNavigateToCreate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(teacherOverviewProvider);
    ref.loadWhenIdle(
      teacherOverviewProvider,
      (s) => s is TeacherOverviewInitial,
      () => ref.read(teacherOverviewProvider.notifier).load(),
    );

    final studentsState = ref.watch(studentsNotifierProvider);
    final studentCount =
        studentsState is StudentsLoaded ? studentsState.students.length : 0;

    final tasksState = ref.watch(teacherTasksNotifierProvider);
    ref.loadWhenIdle(
      teacherTasksNotifierProvider,
      (s) => s is PagingIdle,
      () => ref
          .read(teacherTasksNotifierProvider.notifier)
          .load(kAllTaskStatuses),
    );

    return AppScrollPage(
      children: [
        _Header(studentCount: studentCount),
        const SectionTitle('掌握度概览'),
        _MasterySummary(overview: overview, ref: ref),
        const SectionTitle('薄弱知识点'),
        _WeakPoints(overview: overview, ref: ref),
        const SectionTitle('最近任务'),
        _buildRecentTasks(context, ref, tasksState, studentsState),
      ],
    );
  }

  Widget _buildRecentTasks(
    BuildContext context,
    WidgetRef ref,
    PagingState<TaskModel> tasksState,
    ChildrenState studentsState,
  ) {
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
      // 「掌握度概览」的重量；但也不能只剩一行灰字——那样用户看不出这是「空」
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

    final nameOf = _studentNameResolver(studentsState);

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
                studentName: nameOf(tasks[i].studentId),
              ),
            ),
          ),
      ],
    );
  }
}

/// 概览页头：标题 + 学生总数徽标（教师整体视角）。
class _Header extends StatelessWidget {
  final int studentCount;
  const _Header({required this.studentCount});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text('班级概览', style: text.titleLarge),
          const SizedBox(width: AppSpacing.sm),
          AppBadge.infoChip('$studentCount 名学生'),
        ],
      ),
    );
  }
}

/// 掌握度概览：已掌握知识点占比 + 活跃错题数（教师整体）。
class _MasterySummary extends StatelessWidget {
  final TeacherOverviewState overview;
  final WidgetRef ref;
  const _MasterySummary({required this.overview, required this.ref});

  @override
  Widget build(BuildContext context) {
    if (overview is TeacherOverviewLoading ||
        overview is TeacherOverviewInitial) {
      return const AppLoading.skeletonInline(skeletonLines: 2);
    }
    if (overview is TeacherOverviewError) {
      return AppError(
        message: (overview as TeacherOverviewError).message,
        onRetry: () => ref.read(teacherOverviewProvider.notifier).load(),
      );
    }
    final loaded = overview as TeacherOverviewLoaded;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          _StatRow(
            icon: LucideIcons.lightbulb,
            label: '已掌握知识点',
            value: '${loaded.masteredCount} / ${loaded.totalKnowledgePoints}',
          ),
          const SizedBox(height: AppSpacing.xs),
          _StatRow(
            icon: LucideIcons.alertTriangle,
            label: '活跃错题',
            value: '${loaded.activeWrong}',
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: text.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 薄弱知识点：按活跃错题数降序，给出可一键「就这个出题」的速览（教师整体）。
class _WeakPoints extends StatelessWidget {
  final TeacherOverviewState overview;
  final WidgetRef ref;
  const _WeakPoints({required this.overview, required this.ref});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    if (overview is TeacherOverviewLoading ||
        overview is TeacherOverviewInitial) {
      return const AppLoading.skeletonInline(skeletonLines: 3);
    }
    if (overview is TeacherOverviewError) {
      return AppError(
        message: (overview as TeacherOverviewError).message,
        onRetry: () => ref.read(teacherOverviewProvider.notifier).load(),
      );
    }
    final loaded = overview as TeacherOverviewLoaded;
    if (loaded.weakItems.isEmpty) {
      return AppCard(
        child: AppEmptyState.inline(
          icon: LucideIcons.checkCircle2,
          title: '暂无薄弱知识点',
          message: '目前没有活跃错题，继续保持～',
        ),
      );
    }
    final items = loaded.weakItems.take(6).toList();
    return Column(
      children: [
        for (final item in items)
          AppCard.listRow(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppTags.subject(
                      SubjectAccent.fromName(item.subject),
                      label: item.subject,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        item.knowledgePoint,
                        style: AppTheme.textOf(context).bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '正确率 ${(item.accuracy * 100).round()}% · ${item.activeWrong} 题待复习',
                  style: AppTheme.textOf(context)
                      .bodySmall
                      ?.copyWith(color: app.onSurfaceVariant),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppTextAction(
                    label: '就这个出题',
                    semanticLabel: '就${item.knowledgePoint}出题',
                    onPressed: () {
                      ref.read(taskFormPrefillProvider.notifier).state =
                          TaskFormPrefill(knowledgePoint: item.knowledgePoint);
                      ref
                          .read(shellNavigationProvider.notifier)
                          .request(ShellDestination.teacherCreateTask);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// studentId → 昵称 解析器（无匹配返回 null）。
String? Function(String?) _studentNameResolver(ChildrenState state) {
  final map = <String, String>{};
  if (state is StudentsLoaded) {
    for (final c in state.students) {
      map[c.id] = c.displayName;
    }
  }
  return (String? id) => id == null ? null : map[id];
}

/// 概览「最近任务」单行：标题 + 状态 + 对应学生。
/// 卡片外壳由调用方用 [AppCard.listRow] 提供（列表降噪 + 可点）。
class _RecentTaskRow extends StatelessWidget {
  final TaskModel task;
  final String? studentName;
  const _RecentTaskRow({required this.task, this.studentName});

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
        if (studentName != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Text(
              studentName!,
              style: AppTheme.textOf(context)
                  .labelSmall
                  ?.copyWith(color: app.onSurfaceVariant),
            ),
          ),
        _statusTag(task.status),
        const SizedBox(width: AppSpacing.xs),
        Icon(LucideIcons.chevronRight, size: 16, color: app.onSurfaceVariant),
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
