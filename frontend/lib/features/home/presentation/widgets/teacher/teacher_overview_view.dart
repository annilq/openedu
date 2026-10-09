import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/presentation/paging.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/load_once.dart';
import '../../../../../shared/widgets/app_scroll_page.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_section_title.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../analytics/presentation/providers/analytics_notifier_provider.dart';
import '../../../../students/presentation/providers/students_notifier.dart';
import '../../../../students/providers/students_provider.dart';
import '../../providers/teacher_tasks_notifier.dart';
import '../../providers/teacher_todo_provider.dart';
import 'teacher_todo_section.dart';
import 'workbench_analysis.dart';
import 'workbench_glance.dart';

/// 教师工作台（ADR-0075 §2.2，合并原「概览」与「统计」）。
///
/// 三段式组合，单一 landing 入口：
///  1. **任务区**（非统计，原样保留）：学生总数徽标 + 待办 + 最近任务（top 4）。
///  2. **速览层** [WorkbenchGlance]：作用域固定 `all` 的三块总览图表
///     （掌握度环形 / 薄弱知识点 / 正确率 / 错题分布），替代原概览的纯文字指标行。
///  3. **分析层** [WorkbenchAnalysis]：迁移自统计页 body，作用域 all/class + 维度四选
///     下钻的三聚合图表。
///
/// 数据层去重：删除原 [teacherOverviewProvider]，速览层改走
/// [analyticsSummaryProvider]（只读 `scope=all`），与分析层 [analyticsNotifierProvider]
/// 隔离，避免重复消费同一仓库。
///
/// [onDrill] 由薄弱知识点 / 掌握度条点击触发：目前接线为把分析层切到知识点维度
/// （默认即知识点，确保分析层已在该维度展示该知识点的掌握度）。
class TeacherOverviewView extends ConsumerWidget {
  final void Function(TaskModel) onNavigateToReview;

  /// 空态出口：跳到「任务」页发布任务。
  final VoidCallback? onNavigateToCreate;

  /// 工作台待办卡片点击：按 Tab 深链到任务列表（0=草稿 / 1=进行中 / 2=已完成）。
  final void Function(int tab)? onNavigateToList;

  const TeacherOverviewView({
    super.key,
    required this.onNavigateToReview,
    this.onNavigateToCreate,
    this.onNavigateToList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final todoState = ref.watch(teacherTodoProvider);
    ref.loadWhenIdle(
      teacherTodoProvider,
      (s) => s is TeacherTodoInitial,
      () => ref.read(teacherTodoProvider.notifier).load(),
    );

    // 钻取：薄弱知识点 / 掌握度条点击 → 分析层切到知识点维度（预选该知识点）。
    void onDrill(String knowledgePoint) {
      ref.read(analyticsNotifierProvider.notifier).setDimension('knowledge_point');
    }

    return AppScrollPage(
      children: [
        _Header(studentCount: studentCount),
        if (onNavigateToList != null) ...[
          const SectionTitle('待办'),
          TeacherTodoSection(
              state: todoState, onOpenList: onNavigateToList!, ref: ref),
        ],
        const SectionTitle('最近任务'),
        _buildRecentTasks(context, ref, tasksState, studentsState),
        const SizedBox(height: AppSpacing.lg),
        const SectionTitle('学情速览'),
        WorkbenchGlance(onDrill: onDrill),
        const SizedBox(height: AppSpacing.lg),
        const SectionTitle('学情分析'),
        WorkbenchAnalysis(onDrill: onDrill),
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
            message: '发布任务后，最近 4 条会显示在这里。',
            actionLabel: onNavigateToCreate == null ? null : '去发布任务',
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

/// 工作台页头：标题 + 学生总数徽标（教师整体视角）。
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
          Text('工作台', style: text.titleLarge),
          const SizedBox(width: AppSpacing.sm),
          AppBadge.infoChip('$studentCount 名学生'),
        ],
      ),
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
