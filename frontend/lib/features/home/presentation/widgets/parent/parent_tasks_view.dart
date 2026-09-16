import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_card_list.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../../shared/widgets/app_paging_footer.dart';
import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/presentation/paging.dart';
import '../../../../children/providers/children_provider.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../providers/parent_tasks_notifier.dart';

/// 家长「任务」管理页：按状态分 Tab（草稿 / 进行中 / 已完成），
/// 列表复用后端 GET /tasks 全量数据，卡片点击深链到复核页。
class ParentTasksView extends ConsumerStatefulWidget {
  final void Function(TaskModel task) onNavigateToReview;

  /// 空态主行动：跳到「布置任务」页。空态若不给出口就是一个死胡同——
  /// 用户知道没有任务，但不知道下一步该点哪。
  final VoidCallback? onNavigateToCreate;

  const ParentTasksView({
    super.key,
    required this.onNavigateToReview,
    this.onNavigateToCreate,
  });

  @override
  ConsumerState<ParentTasksView> createState() => _ParentTasksViewState();
}

class _ParentTasksViewState extends ConsumerState<ParentTasksView> {
  // 0=草稿(draft+ready)  1=进行中(assigned)  2=已完成(done)
  int _tab = 0;

  /// 触底自动加载下一页（ADR-0053）：任务只增不减，一次拉全量会越来越慢。
  late final ScrollController _scroll = ScrollController();
  VoidCallback? _unbindScroll;

  @override
  void initState() {
    super.initState();
    _unbindScroll = bindPagingOnScroll(
      _scroll,
      () => ref.read(parentTasksNotifierProvider.notifier).loadMore(),
    );
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _unbindScroll?.call();
    _scroll.dispose();
    super.dispose();
  }

  /// 换 Tab = 换一次查询。
  ///
  /// 状态过滤在**服务端**：分页之后客户端过滤只会过滤已加载的页，Tab 会漏数据。
  void _switchTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    _reload();
  }

  void _reload() => ref
      .read(parentTasksNotifierProvider.notifier)
      .load(kParentTaskTabStatuses[_tab]);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(parentTasksNotifierProvider);
    final childrenState = ref.watch(childrenNotifierProvider);
    final nameOf = _childNameResolver(childrenState);

    if (state is PagingIdle || state.isLoading) {
      return const AppLoading(message: '加载任务…');
    }
    final error = state.errorOrNull;
    if (error != null) return AppError(message: error, onRetry: _reload);
    return _buildBody(context, state, nameOf);
  }

  Widget _buildBody(BuildContext context, PagingState<TaskModel> state,
      String? Function(String?) nameOf) {
    // 徽标取服务端随分页响应下发的全量计数，不是统计已加载页——
    // 否则「已完成 128」会显示成「已完成 20」。
    final counts = taskCountsOf(state);
    final tabCounts = [counts.draftTab, counts.assigned, counts.done];
    final items = state.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
          child: _TabBar(
            tab: _tab,
            counts: tabCounts,
            onTap: _switchTab,
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState(tabCounts)
              : LayoutBuilder(
                  // 列数只看可用宽度（ADR-0045）：不碰 MediaQuery / 方向 / 平台。
                  builder: (context, constraints) => CustomScrollView(
                        controller: _scroll,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                                AppLayout.listGutter,
                                AppSpacing.sm,
                                AppLayout.listGutter,
                                AppSpacing.xl2),
                            sliver: AppCardSliver(
                              width: constraints.maxWidth,
                              itemCount: items.length,
                              itemBuilder: (_, i) => _TaskCard(
                                task: items[i],
                                childName: nameOf(items[i].childId),
                                onTap: () => widget.onNavigateToReview(items[i]),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppLayout.listGutter),
                              child: AppPagingFooter(
                                hasMore: state.hasMore,
                                isLoadingMore: state.isLoadingMore,
                                moreError: state.moreError,
                                remaining: state.remaining,
                                onLoadMore: () => ref
                                    .read(parentTasksNotifierProvider.notifier)
                                    .loadMore(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  /// 空态。三个 Tab 的「空」含义完全不同，不能共用一句「暂无任务」——
  /// 那是把「为什么空」和「下一步做什么」都推给了用户。
  ///
  /// 两条判据：
  /// - **[counts] 全为 0** = 家长从没布置过任务（首次空）→ 讲流程（[steps]），
  ///   因为用户还不知道这个页面是干什么的；
  /// - **只有当前 Tab 为 0** = 流程跑通过，只是这批数据不在这个状态 → 指路到
  ///   真正有数据的那个 Tab，避免把用户送进另一个空页面。
  Widget _buildEmptyState(List<int> counts) {
    final draftCount = counts[0];
    final assignedCount = counts[1];
    final allEmpty = draftCount + assignedCount + counts[2] == 0;
    final goCreate = widget.onNavigateToCreate;

    return switch (_tab) {
      // 草稿：出了题、还没派发出去。
      0 => AppEmptyState(
          icon: LucideIcons.notebookPen,
          title: allEmpty ? '还没有布置过任务' : '草稿箱是空的',
          message: allEmpty
              ? '按学科与知识点让 AI 出一套题，复核后派给娃娃，做完自动进复习队列。'
              : '任务都已经派发或完成了。想再布置一套，回到「布置任务」。',
          actionLabel: '去布置任务',
          actionIcon: LucideIcons.plus,
          onAction: goCreate,
          steps: allEmpty
              ? const [
                  '选学科与知识点，让 AI 出题',
                  '复核题目、删掉不合适的',
                  '派给娃娃，完成后自动归档',
                ]
              : null,
        ),
      // 进行中：已派发、娃娃还没做完。
      1 => AppEmptyState(
          icon: LucideIcons.hourglass,
          title: '没有进行中的任务',
          message: allEmpty
              ? '还没有布置过任务。先去布置一套，派发给娃娃后就会进入「进行中」。'
              : draftCount > 0
                  ? '草稿箱里还有 $draftCount 个任务没派发，派发后就会出现在这里。'
                  : '任务都已完成。娃娃做完后会自动归档到「已完成」。',
          actionLabel:
              allEmpty ? '去布置任务' : (draftCount > 0 ? '去派发草稿' : '查看已完成'),
          actionIcon: allEmpty ? LucideIcons.plus : null,
          onAction: allEmpty
              ? goCreate
              : (draftCount > 0 ? () => _switchTab(0) : () => _switchTab(2)),
        ),
      // 已完成：娃娃做完后归档的位置。
      _ => AppEmptyState(
          icon: LucideIcons.checkCircle2,
          title: '还没有完成的任务',
          message: allEmpty
              ? '还没有布置过任务。布置并派发后，娃娃做完会归档到这里。'
              : assignedCount > 0
                  ? '有 $assignedCount 个任务正在进行中，娃娃做完后会归档到这里。'
                  : '草稿箱里还有 $draftCount 个任务等待派发。',
          actionLabel:
              allEmpty ? '去布置任务' : (assignedCount > 0 ? '查看进行中' : '去派发草稿'),
          actionIcon: allEmpty ? LucideIcons.plus : null,
          onAction: allEmpty
              ? goCreate
              : (assignedCount > 0 ? () => _switchTab(1) : () => _switchTab(0)),
        ),
    };
  }
}

/// 状态 Tab 栏：选中态实色，未选描边；后缀数量徽标。
class _TabBar extends StatelessWidget {
  final int tab;
  final List<int> counts;
  final void Function(int) onTap;
  const _TabBar({required this.tab, required this.counts, required this.onTap});

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
          return Expanded(
              child: Padding(
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
  const _TaskCard({required this.task, this.childName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return PopIn(
      key: ValueKey(task.id),
      child: AppCard.listRow(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
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
              _meta(context, app, '${task.displayQuestionCount} 题'),
              if (childName != null) _meta(context, app, '派给 $childName'),
              if (task.createdAt != null)
                _meta(context, app, _formatDate(task.createdAt!)),
            ],
          ),
        ],
      ),
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
