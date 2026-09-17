import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_card_list.dart';
import '../../../../../shared/widgets/app_dialog.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../../shared/widgets/app_paging_footer.dart';
import '../../../../../shared/widgets/app_select_strip.dart';
import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/presentation/paging.dart';
import '../../../../children/providers/children_provider.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../../../export/domain/export_repository.dart';
import '../../../../export/presentation/export_preview_page.dart';
import '../../providers/parent_tasks_notifier.dart';

/// 家长「任务」管理页：按状态分 Tab（草稿 / 进行中 / 已完成），
/// 列表复用后端 GET /tasks 全量数据，卡片点击深链到复核页。
/// 支持多选导出打印（ADR-0052）：勾选若干任务，纸上按任务分节印快照。
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

  /// 多选导出态（ADR-0052）：勾选若干任务 → 一份 PDF 按任务分节。
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  /// 「已完成」按月分段后，更早的月份是否展开（ADR-0053 P2）。
  ///
  /// 默认只展开最近 3 个月：这个 Tab 的用途是「回看最近做完了什么」，
  /// 半年前的卷子默认铺开只会把最近的东西挤下去。
  bool _olderExpanded = false;

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
    setState(() {
      _tab = i;
      // 换 Tab 就收起「更早」：上个月展开过不代表这个月也想展开。
      _olderExpanded = false;
      // 换 Tab = 换一批数据，选择态随之清空——勾选的是「这批任务」，
      // 列表内容变了还留着旧勾选只会让人误印。
      _selecting = false;
      _selectedIds.clear();
    });
    _reload();
  }

  void _toggleSelect(String id) => setState(() {
        _selectedIds.contains(id)
            ? _selectedIds.remove(id)
            : _selectedIds.add(id);
      });

  void _toggleSelectAll() {
    final state = ref.read(parentTasksNotifierProvider);
    final allSelected =
        state.items.isNotEmpty && _selectedIds.length == state.items.length;
    setState(() {
      allSelected ? _selectedIds.clear() : _selectedIds.addAll(
        state.items.map((t) => t.id),
      );
    });
  }

  void _exitSelecting() => setState(() {
        _selecting = false;
        _selectedIds.clear();
      });

  /// 导出勾选的任务（ADR-0052）：单一来源、永远一份、按任务分节印快照。
  Future<void> _exportSelectedTasks(List<TaskModel> items) async {
    final selected = [
      for (final t in items)
        if (_selectedIds.contains(t.id)) t,
    ];
    if (selected.isEmpty) return;
    if (selected.length > kExportSoftLimit) {
      // 软提示不硬拦：服务端另有硬边界，客户端只提醒排版耗时。
      final confirmed = await AppDialog.confirm(
        context,
        title: const Text('题目较多'),
        content: const Text('一次导出的任务较多，打印预览可能变慢，建议分批导出。'),
        confirmLabel: '继续导出',
      );
      if (confirmed != true || !mounted) return;
    }
    final title = selected.length == 1 ? selected.first.title : '任务练习';
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ExportPreviewPage(
          request: ExportSheetRequest(source: 'task', ids: _selectedIds.toList()),
          title: title,
        ),
      ),
    );
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
        // 多选导出条（ADR-0052）：入口放在这里而非顶栏——AppTopBar 的
        // trailing 槽位只有 40px，且导出动作在选中后才出现。
        AppSelectStrip(
          selecting: _selecting,
          selectedCount: _selectedIds.length,
          totalCount: items.length,
          onEnterSelecting: () => setState(() => _selecting = true),
          onToggleSelectAll: _toggleSelectAll,
          hintText: '勾选要打印的任务',
        ),
        if (_selecting && _selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ShadButton(
                  onPressed: () => _exportSelectedTasks(items),
                  leading: const Icon(LucideIcons.printer, size: 16),
                  child: Text('导出打印 (${_selectedIds.length})'),
                ),
                ShadButton.outline(
                  onPressed: _exitSelecting,
                  child: const Text('退出多选'),
                ),
              ],
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
                            sliver: _tab == 2
                                ? _MonthSections(
                                    items: items,
                                    olderExpanded: _olderExpanded,
                                    onExpandOlder: () =>
                                        setState(() => _olderExpanded = true),
                                    cardBuilder: (task) => _buildTaskCard(
                                      context,
                                      task,
                                      nameOf(task.childId),
                                    ),
                                  )
                                : AppCardSliver(
                                    width: constraints.maxWidth,
                                    itemCount: items.length,
                                    itemBuilder: (_, i) => _buildTaskCard(
                                      context,
                                      items[i],
                                      nameOf(items[i].childId),
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

  /// 任务卡：多选态下点击 = 切换勾选（选中描边转 primary，与题库页同语言），
  /// 普通态下点击 = 进复核页。
  Widget _buildTaskCard(BuildContext context, TaskModel task, String? childName) {
    final selected = _selectedIds.contains(task.id);
    return _TaskCard(
      task: task,
      childName: childName,
      selected: _selecting && selected,
      showCheckbox: _selecting,
      onTap: _selecting
          ? () => _toggleSelect(task.id)
          : () => widget.onNavigateToReview(task),
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

/// 「已完成」按月分段（ADR-0053 P2）。
///
/// 任务**不加归档字段**——`done` 已经是终态，再加 `archived` 会造出「done 但未归档 /
/// 已归档但非 done」两种重叠状态，而且没人能回答「什么时候该点归档」。这个 Tab 真正
/// 的痛点不是「怎么归档」，而是「几个月后这里有几千条，找不到最近的那条」。
///
/// 于是按月分段：最近 3 个月展开，更早折叠成一行「2026 年 6 月及以前（42）」。
/// 分段边界由前端按**已加载**的页算，不新增接口——分页之后「更早」本身就随追加
/// 变长，这里只负责把「更早」收起来。
class _MonthSections extends StatelessWidget {
  const _MonthSections({
    required this.items,
    required this.olderExpanded,
    required this.onExpandOlder,
    required this.cardBuilder,
  });

  final List<TaskModel> items;
  final bool olderExpanded;
  final VoidCallback onExpandOlder;
  final Widget Function(TaskModel) cardBuilder;

  /// 默认展开的月数。
  static const int recentMonths = 3;

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static String _monthLabel(String key) {
    final parts = key.split('-');
    return '${parts[0]} 年 ${int.parse(parts[1])} 月';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<TaskModel>>{};
    for (final t in items) {
      // 没有时间戳的任务（旧数据）归到「更早」，不单独起一段。
      groups.putIfAbsent(
        t.createdAt == null ? '' : _monthKey(_parse(t.createdAt!)),
        () => <TaskModel>[],
      ).add(t);
    }
    final months = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final visible =
        olderExpanded ? months.length : months.take(recentMonths).length;

    final entries = <_Row>[];
    for (var i = 0; i < visible; i++) {
      final key = months[i];
      entries.add(_Row.header(key.isEmpty ? '更早' : _monthLabel(key)));
      for (final t in groups[key]!) {
        entries.add(_Row.card(t));
      }
    }
    if (!olderExpanded && months.length > recentMonths) {
      final older = months.skip(recentMonths);
      final count = older.fold<int>(0, (s, m) => s + groups[m]!.length);
      entries.add(_Row.collapsed(
        '${_monthLabel(older.first)}及以前（$count）',
        count,
      ));
    }

    return SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final row = entries[i];
        return switch (row) {
          _HeaderRow(:final label) => Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? 0 : AppSpacing.md,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                label,
                style: AppTheme.textOf(context).titleSmall?.copyWith(
                      color: AppTheme.colorsOf(context).onSurfaceVariant,
                    ),
              ),
            ),
          _CardRow(:final task) => Padding(
              padding: const EdgeInsets.only(bottom: AppLayout.listRowGap),
              child: cardBuilder(task),
            ),
          _CollapsedRow(:final label) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: AppCard.listRow(
                margin: EdgeInsets.zero,
                onTap: onExpandOlder,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const Icon(LucideIcons.chevronDown, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        label,
                        style: AppTheme.textOf(context).bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        };
      },
    );
  }

  static DateTime _parse(String iso) =>
      DateTime.tryParse(iso) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// [_MonthSections] 的一行：月标题 / 卡片 / 「更早」折叠入口。
sealed class _Row {
  const _Row();

  const factory _Row.header(String label) = _HeaderRow;
  const factory _Row.card(TaskModel task) = _CardRow;
  const factory _Row.collapsed(String label, int count) = _CollapsedRow;
}

class _HeaderRow extends _Row {
  final String label;
  const _HeaderRow(this.label);
}

class _CardRow extends _Row {
  final TaskModel task;
  const _CardRow(this.task);
}

class _CollapsedRow extends _Row {
  final String label;
  final int count;
  const _CollapsedRow(this.label, this.count);
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

  /// 多选态（ADR-0052）：勾选框 + 选中描边转 primary（与题库页同语言）。
  final bool showCheckbox;
  final bool selected;
  const _TaskCard({
    required this.task,
    this.childName,
    required this.onTap,
    this.showCheckbox = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return PopIn(
      key: ValueKey(task.id),
      child: AppCard.listRow(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        border: Border.all(
          color: selected ? app.primary : AppBrutal.ink,
          width: 1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
                      if (childName != null)
                        _meta(context, app, '派给 $childName'),
                      if (task.createdAt != null)
                        _meta(context, app, _formatDate(task.createdAt!)),
                    ],
                  ),
                ],
              ),
            ),
            if (showCheckbox) ...[
              const SizedBox(width: AppSpacing.sm),
              ShadCheckbox(
                value: selected,
                onChanged: (_) => onTap(),
              ),
            ],
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
