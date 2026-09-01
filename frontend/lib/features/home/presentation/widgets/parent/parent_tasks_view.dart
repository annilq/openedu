import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/domain/models/models.dart';
import '../../../../children/domain/providers/children_provider.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../providers/parent_tasks_notifier.dart';

/// 家长「任务」管理页：按状态分 Tab（草稿 / 进行中 / 已完成），
/// 列表复用后端 GET /tasks 全量数据，卡片点击深链到复核页。
class ParentTasksView extends ConsumerStatefulWidget {
  final void Function(TaskModel task) onNavigateToReview;
  const ParentTasksView({super.key, required this.onNavigateToReview});

  @override
  ConsumerState<ParentTasksView> createState() => _ParentTasksViewState();
}

class _ParentTasksViewState extends ConsumerState<ParentTasksView> {
  // 0=草稿(draft+ready)  1=进行中(assigned)  2=已完成(done)
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(parentTasksNotifierProvider.notifier).load());
  }

  List<TaskModel> _filter(List<TaskModel> all) {
    switch (_tab) {
      case 1:
        return all.where((t) => t.status == 'assigned').toList();
      case 2:
        return all.where((t) => t.status == 'done').toList();
      default:
        return all.where((t) => t.status == 'draft' || t.status == 'ready').toList();
    }
  }

  String _tabLabel(int tab) => const ['草稿', '进行中', '已完成'][tab];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(parentTasksNotifierProvider);
    final childrenState = ref.watch(childrenNotifierProvider);
    final nameOf = _childNameResolver(childrenState);

    return state is ParentTasksLoading
        ? const AppLoading(message: '加载任务…')
        : state is ParentTasksError
            ? AppError(
                message: state.message,
                onRetry: () =>
                    ref.read(parentTasksNotifierProvider.notifier).load(),
              )
            : _buildBody(context, state, nameOf);
  }

  Widget _buildBody(BuildContext context, ParentTasksState state,
      String? Function(String?) nameOf) {
    final all = state is ParentTasksLoaded ? state.tasks : const <TaskModel>[];
    final counts = [
      all.where((t) => t.status == 'draft' || t.status == 'ready').length,
      all.where((t) => t.status == 'assigned').length,
      all.where((t) => t.status == 'done').length,
    ];
    final items = _filter(all);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl2, AppSpacing.xl2, AppSpacing.xl2, AppSpacing.md),
          child: _TabBar(
            tab: _tab,
            counts: counts,
            onTap: (i) => setState(() => _tab = i),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _EmptyState(tab: _tabLabel(_tab))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl2,
                      AppSpacing.sm, AppSpacing.xl2, AppSpacing.xl4),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => _TaskCard(
                    task: items[i],
                    childName: nameOf(items[i].childId),
                    onTap: () => widget.onNavigateToReview(items[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 状态 Tab 栏：选中态实色，未选描边；后缀数量徽标。
class _TabBar extends StatelessWidget {
  final int tab;
  final List<int> counts;
  final void Function(int) onTap;
  const _TabBar(
      {required this.tab, required this.counts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final labels = const ['草稿', '进行中', '已完成'];
    return Row(
      children: List.generate(3, (i) {
        final selected = tab == i;
        final btn = selected
            ? ShadButton(
                onPressed: () => onTap(i),
                child: Text('${labels[i]} ${counts[i]}'),
              )
            : ShadButton.outline(
                onPressed: () => onTap(i),
                child: Text('${labels[i]} ${counts[i]}'),
              );
        if (i < 2) {
          return Expanded(child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: btn,
          ));
        }
        return Expanded(child: btn);
      }),
    );
  }
}

/// 单个任务卡片。
class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final String? childName;
  final VoidCallback onTap;
  const _TaskCard(
      {required this.task, this.childName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: AppTheme.textOf(context).titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _statusTag(task.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _meta(context, app, '${task.questions.length} 题'),
              if (childName != null) _meta(context, app, '派给 $childName'),
              if (task.createdAt != null)
                _meta(context, app, _formatDate(task.createdAt!)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, AppColors app, String text) => Text(
        text,
        style: AppTheme.textOf(context).labelSmall?.copyWith(
              color: app.onSurfaceVariant,
            ),
      );

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

class _EmptyState extends StatelessWidget {
  final String tab;
  const _EmptyState({required this.tab});
  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.listTodo, size: 40, color: app.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text('暂无$tab任务',
              style: AppTheme.textOf(context).bodyLarge?.copyWith(
                    color: app.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}

/// 由 children 状态构造 childId→昵称 解析器（无匹配返回 null）。
String? Function(String?) _childNameResolver(ChildrenState state) {
  final map = <String, String>{};
  if (state is ChildrenLoaded) {
    for (final c in state.children) {
      map[c.id] = c.displayName;
    }
  }
  return (String? id) => id == null ? null : map[id];
}

String _formatDate(String iso) {
  // 后端 created_at 形如 2026-09-01T15:04:00；取日期部分。
  final t = iso.split('T');
  if (t.isEmpty) return iso;
  final date = t[0];
  final parts = date.split('-');
  if (parts.length == 3) return '${parts[1]}-${parts[2]}';
  return date;
}
