import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/presentation/paging.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/question_labels.dart';
import '../../../../../shared/widgets/app_card_list.dart';
import '../../../../../shared/widgets/app_content_frame.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_paging_footer.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../export/domain/export_repository.dart';
import '../../../../export/presentation/export_confirm.dart';
import '../../../../export/presentation/export_preview_page.dart';
import '../../providers/question_bank_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// 题库视图（产品闭环）：年级 segment 切换 + 学科/题型/关键词过滤 + 多选，
/// 支持「用这些题生成任务」（选项 A）与「加入已有草稿」（选项 B）。
/// 两个动作成功后均跳 ParentTaskReviewScreen，复用现有锁定/派发/练习链路。
class ParentQuestionBankView extends ConsumerStatefulWidget {
  final void Function(TaskModel task) onNavigateToReview;
  const ParentQuestionBankView({super.key, required this.onNavigateToReview});

  @override
  ConsumerState<ParentQuestionBankView> createState() =>
      _ParentQuestionBankViewState();
}

class _ParentQuestionBankViewState
    extends ConsumerState<ParentQuestionBankView> {
  static const List<String> _subjects = [
    '数学',
    '语文',
    '英语',
    '科学',
    '道法',
    '历史',
    '地理',
    '生物',
    '物理',
    '化学'
  ];
  static const List<String> _qtypes = ['calc', 'fill', 'choice', 'open'];
  static const List<String> _qtypeLabels = ['计算', '填空', '选择', '应用'];

  String _selectedSubject = ''; // '' = 全部
  String _selectedQtype = 'all'; // 'all' = 全部
  int _gradeSegment = -1; // -1 = 全部
  /// 归档范围（ADR-0053 P2）：active = 只看在用（默认），archived = 只看已归档，all = 含已归档。
  String _archived = 'active';
  final Set<String> _selectedIds = {};
  final TextEditingController _keywordCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController(text: '题库组卷');
  Timer? _debounce;

  /// 整页滚动控制器：题库页的筛选区与列表在同一个滚动容器里，触底即追加下一页
  /// （ADR-0053）。此前列表永远只有第一页 20 条，第 21 条之后的题看不到。
  late final ScrollController _scroll = ScrollController();
  VoidCallback? _unbindScroll;

  @override
  void initState() {
    super.initState();
    _unbindScroll = bindPagingOnScroll(
      _scroll,
      () => ref.read(questionBankNotifierProvider.notifier).loadMore(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(questionBankNotifierProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _unbindScroll?.call();
    _scroll.dispose();
    _keywordCtrl.dispose();
    _titleCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    ref.read(questionBankNotifierProvider.notifier).load(
          gradeSegment: _gradeSegment,
          subject: _selectedSubject.isEmpty ? null : _selectedSubject,
          qtype: _selectedQtype == 'all' ? null : _selectedQtype,
          keyword: _keywordCtrl.text.trim().isEmpty
              ? null
              : _keywordCtrl.text.trim(),
          archived: _archived,
        );
  }

  /// 切归档范围：与学科 / 年级同级，换了就重新取第一页。
  ///
  /// 不在客户端过滤已加载的页——那样只会过滤当前页，后面几页里混着的已归档题
  /// 又会冒出来（P0 把「客户端过滤」从任务 Tab 里拿掉是同一个理由）。
  void _switchArchived(String value) {
    if (value == _archived) return;
    setState(() => _archived = value);
    _reload();
  }

  Future<void> _archiveSelected(bool archived) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    await ref
        .read(questionBankNotifierProvider.notifier)
        .archiveQuestions(ids, archived: archived);
  }

  /// 导出打印（ADR-0052）：题库来源，服务端按 id 装配、按学科分节。
  ///
  /// 装配在服务端——客户端只传「选了谁」；降级题数（含公式 / 图片、
  /// 按纯文本打印）由客户端自算并如实提示，因为题面数据本来就在手上。
  Future<void> _exportSelected() async {
    final state = ref.read(questionBankNotifierProvider);
    final selected = state is BankLoaded
        ? [
            for (final item in state.page.items)
              if (_selectedIds.contains(item.id)) item,
          ]
        : <BankQuestionItem>[];
    final downgraded = countDowngradedQuestions(
      stems: selected.map((e) => e.stem),
      optionLists: selected.map((e) => e.options),
    );

    // 软提示不硬拦：家长要印 100 题的复习卷是合理需求（服务端另有硬边界）。
    final proceed = await confirmLargeExport(
      context,
      count: _selectedIds.length,
      unit: '题目',
    );
    if (!proceed || !mounted) return;
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ExportPreviewPage(
          request: ExportSheetRequest(source: 'bank', ids: _selectedIds.toList()),
          title: '题库练习',
          downgradedCount: downgraded,
        ),
      ),
    );
  }

  void _onKeywordChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  void _toggle(String id) => setState(() => _selectedIds.contains(id)
      ? _selectedIds.remove(id)
      : _selectedIds.add(id));

  Future<void> _generate() async {
    final selected = ref.read(selectedChildProvider);
    if (selected == null) {
      AppToast.show(context, '请先在侧栏选择娃娃');
      return;
    }
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await _showCreateDialog();
    if (ok != true) return;
    await ref.read(questionBankNotifierProvider.notifier).createTaskFromBank(
          title:
              _titleCtrl.text.trim().isEmpty ? '题库组卷' : _titleCtrl.text.trim(),
          childId: selected.id,
          ids: ids,
        );
  }

  Future<bool?> _showCreateDialog() {
    return showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('用这些题生成任务'),
        description: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: AppTextField(label: '试卷标题', controller: _titleCtrl),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('生成'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToDraft() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final drafts =
        await ref.read(questionBankNotifierProvider.notifier).fetchDraftTasks();
    if (!mounted) return;
    if (drafts.isEmpty) {
      AppToast.show(context, '暂无草稿任务，请先「用这些题生成任务」');
      return;
    }
    final picked = await _showDraftPicker(drafts);
    if (picked == null) return;
    await ref.read(questionBankNotifierProvider.notifier).addToTaskFromBank(
          taskId: picked,
          ids: ids,
        );
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await _showDeleteConfirm(ids.length);
    if (ok != true) return;
    await ref.read(questionBankNotifierProvider.notifier).deleteQuestions(ids);
  }

  Future<bool?> _showDeleteConfirm(int count) {
    return showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('删除题库题目'),
        description: Text(
          '确认删除选中的 $count 道题？已被任务引用的题将不会被删除。此操作不可撤销。',
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(ctx).pop(true),
            leading: const Icon(LucideIcons.trash2, size: 16),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 闭环「用过 N 次 → 在哪里用」：弹出引用该题库题的任务列表。
  Future<void> _showUsages(BankQuestionItem q) async {
    List<QuestionUsageItem> usages;
    try {
      usages = await ref
          .read(questionBankNotifierProvider.notifier)
          .fetchQuestionUsages(q.id);
    } catch (e) {
      if (mounted) AppToast.error(context, '加载引用失败');
      return;
    }
    if (!mounted) return;
    final app = AppTheme.colorsOf(context);
    final preview = q.stem.length > 16 ? '${q.stem.substring(0, 16)}…' : q.stem;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('「$preview」被以下任务使用'),
        message: usages.isEmpty ? const Text('暂未在任何任务中使用') : null,
        actions: [
          for (final u in usages)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openTask(u.taskId);
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      u.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: app.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      statusLabel(u.status),
                      style: AppTheme.textOf(context).labelSmall?.copyWith(
                            color: app.onSecondaryContainer,
                          ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.arrowUpRight,
                      size: 14, color: app.onSurfaceVariant),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 从引用列表跳转到对应任务的复核页（先拉完整任务再跳转）。
  Future<void> _openTask(String taskId) async {
    try {
      final task = await ref
          .read(questionBankNotifierProvider.notifier)
          .fetchTaskById(taskId);
      if (!mounted) return;
      widget.onNavigateToReview(task);
    } catch (e) {
      if (mounted) AppToast.error(context, '打开任务失败');
    }
  }

  Future<String?> _showDraftPicker(List<TaskModel> drafts) {
    return showShadDialog<String?>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('加入已有草稿'),
        description: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ListView.separated(
            itemCount: drafts.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (_, i) {
              final t = drafts[i];
              final app = AppTheme.colorsOf(ctx);
              // 走 AppFocusableAction：裸 GestureDetector 不进焦点树，
              // 桌面端 Tab 跳不过来、Enter 选不中（ADR-0046）。
              return AppFocusableAction(
                onTap: () => Navigator.of(ctx).pop(t.id),
                hoverHighlight: true,
                semanticLabel: '用《${t.title}》出题',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: app.outline,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, style: AppTheme.textOf(ctx).bodyMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${t.questions.length} 题 · ${statusLabel(t.status)}',
                        style: AppTheme.textOf(ctx)
                            .labelSmall
                            ?.copyWith(color: app.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(questionBankNotifierProvider);
    final app = AppTheme.colorsOf(context);
    final busy = state is BankActionLoading;

    ref.listen<BankState>(questionBankNotifierProvider, (prev, next) {
      if (next is BankActionSuccess) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(questionBankNotifierProvider.notifier).reset();
          widget.onNavigateToReview(next.task);
        });
      } else if (next is BankDeleted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final msg = next.skippedInUse > 0 || next.skippedForbidden > 0
              ? '已删除 ${next.deleted} 题；'
                  '${next.skippedInUse} 题已被任务引用未删'
                  '${next.skippedForbidden > 0 ? '，${next.skippedForbidden} 题无权限' : ''}'
              : '已删除 ${next.deleted} 题';
          AppToast.show(context, msg);
          _selectedIds.clear();
          _reload();
        });
      } else if (next is BankArchived) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          AppToast.show(
            context,
            next.archived
                ? '已归档 ${next.updated} 题（可随时恢复）'
                : '已恢复 ${next.updated} 题',
          );
          _selectedIds.clear();
          _reload();
        });
      } else if (next is BankActionError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) AppToast.error(context, next.message);
        });
      }
    });

    // 与概览 / 布置任务 / 错题本等家长页完全一致的页面骨架：
    // 整页 SingleChildScrollView + 居中约束 maxWidth 1080 + SectionTitle + 内容置于 AppCard。
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
      child: AppContentFrame(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('题库'),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _buildCardContent(state, app, busy),
            ),
          ],
        ),
      ),
    );
  }

  /// 筛选区（学科 / 题型 / 年级 / 关键词）。放在卡片顶部，随页面一起滚动，
  /// 与「错题本」等页面「SectionTitle + AppCard(内嵌内容)」的结构保持一致。
  Widget _buildFilters(dynamic app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _gradeChip(-1, '全部'),
              for (var i = 1; i <= 9; i++) _gradeChip(i, '$i年级'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 160,
              child: AppPickerField<String>(
                label: '学科',
                values: ['', ..._subjects],
                labels: ['全部学科', ..._subjects],
                value: _selectedSubject,
                onChanged: (v) => setState(() {
                  _selectedSubject = v;
                  _reload();
                }),
              ),
            ),
            SizedBox(
              width: 160,
              child: AppPickerField<String>(
                label: '题型',
                values: ['all', ..._qtypes],
                labels: ['全部题型', ..._qtypeLabels],
                value: _selectedQtype,
                onChanged: (v) => setState(() {
                  _selectedQtype = v;
                  _reload();
                }),
              ),
            ),
            SizedBox(
              width: 200,
              child: AppTextField(
                label: '关键词',
                controller: _keywordCtrl,
                onChanged: _onKeywordChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // 归档三态（ADR-0053 P2）。与年级 chip 同一套语言：选中的实色、未选描边。
        // ADR 里写的是 AppSelectStrip，但那个组件是「多选模式条」（计数 + 全选），
        // 与这里的语义不同；复用本页已有的 chip 行才是「全站一种筛选语言」。
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final opt in const [
              ('active', '只看在用'),
              ('all', '含已归档'),
              ('archived', '只看已归档'),
            ])
              _archivedChip(opt.$1, opt.$2),
          ],
        ),
      ],
    );
  }

  Widget _archivedChip(String value, String label) {
    final active = _archived == value;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: active
          ? ShadButton(
              size: ShadButtonSize.sm,
              onPressed: () => _switchArchived(value),
              child: Text(label),
            )
          : ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => _switchArchived(value),
              child: Text(label),
            ),
    );
  }

  Widget _gradeChip(int seg, String label) {
    final active = _gradeSegment == seg;
    void onPressed() => setState(() {
          _gradeSegment = seg;
          _reload();
        });
    final child = Text(label);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: active
          ? ShadButton(
              size: ShadButtonSize.sm,
              onPressed: onPressed,
              child: child,
            )
          : ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onPressed,
              child: child,
            ),
    );
  }

  /// 卡片内容：筛选区 + 分隔 + 题列表 +（选中时）操作区。
  Widget _buildCardContent(BankState state, dynamic app, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilters(app),
        const SizedBox(height: AppSpacing.md),
        Container(height: 1, color: app.outline),
        const SizedBox(height: AppSpacing.md),
        _buildListArea(state, app),
        if (_selectedIds.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Container(height: 1, color: app.outline),
          const SizedBox(height: AppSpacing.md),
          _buildActionFooter(app, busy),
        ],
      ],
    );
  }

  Widget _buildListArea(BankState state, dynamic app) {
    // sealed 穷尽处理：加载/空闲/操作进行中/删除结果/操作成功/失败均先以加载占位，
    // 删除后由 ref.listen 触发 _reload 回到 BankLoaded；避免对 BankLoaded 不安全强转
    // 导致 type 'BankDeleted' is not a subtype of type 'BankLoaded' 崩溃。
    return switch (state) {
      BankLoading() ||
      BankIdle() ||
      BankActionLoading() ||
      BankActionSuccess() ||
      BankActionError() ||
      BankDeleted() ||
      BankArchived() =>
        const AppLoading(),
      BankError(:final message) => AppError(message: message, onRetry: _reload),
      BankLoaded(:final page) => page.items.isEmpty
          ? AppEmptyState(
              icon: LucideIcons.library,
              title: '题库还是空的',
              message: '去「布置任务」生成题目并加入题库，这里就会积累你的专属题集',
              actionLabel: '刷新',
              onAction: _reload,
            )
          : Column(
              children: [
                // 宽度够时排成两列（ADR-0053）：题库一屏能看到的题翻倍。
                // 列表区在卡片内、外层已有滚动容器，所以用非懒加载版。
                LayoutBuilder(
                  builder: (context, constraints) => AppCardList(
                    width: constraints.maxWidth,
                    itemCount: page.items.length,
                    itemBuilder: (_, i) => _buildItem(page.items[i], app),
                  ),
                ),
                AppPagingFooter(
                  hasMore: page.hasMore,
                  isLoadingMore: state.isLoadingMore,
                  moreError: state.moreError,
                  remaining: page.total - page.loaded > 0
                      ? page.total - page.loaded
                      : 0,
                  onLoadMore: () => ref
                      .read(questionBankNotifierProvider.notifier)
                      .loadMore(),
                ),
              ],
            ),
    };
  }

  Widget _buildItem(BankQuestionItem q, dynamic app) {
    final selected = _selectedIds.contains(q.id);
    return AppCard.listRow(
      // 列表行变体：1px 墨黑描边、无阴影（ADR-0044「列表降噪」）。
      // 选中态描边转为 primary，复用 [AppCard.border] 透传。
      // 行距由 AppCardList 统一给，卡片自身零外边距。
      margin: EdgeInsets.zero,
      border: Border.all(
        color: selected ? app.primary : AppBrutal.ink,
        width: 1,
      ),
      onTap: () => _toggle(q.id),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.stem,
                    style: AppTheme.textOf(context)
                        .bodyLarge
                        ?.copyWith(height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _tag(app, q.subject),
                      _tag(app, '${q.grade}年级'),
                      _tag(app, q.knowledgePoint),
                      _tag(app, qtypeLabelFull(q.qtype)),
                      // 已归档的行必须自己说出来：在「含已归档」视图里，
                      // 归档题与在用题长得一样，看不出区别。
                      if (q.archivedAt != null) _tag(app, '已归档'),
                      if (q.usageCount > 0) _usageTag(app, q),
                    ],
                  ),
                ],
              ),
            ),
            ShadCheckbox(
              value: selected,
              onChanged: (_) => _toggle(q.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(dynamic app, String text, {Color? tone}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: app.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: AppTheme.textOf(context).labelSmall?.copyWith(
              color: tone ?? app.onSurfaceVariant,
            ),
      ),
    );
  }

  /// 「用过 N 次」标签：可点击，弹出引用任务列表（闭环「用过 → 在哪里用」）。
  ///
  /// 走 [AppFocusableAction] 而非裸 `GestureDetector`——后者不进焦点树
  /// （ADR-0046）。焦点环圆角跟随标签自身的 [AppRadius.sm]。
  Widget _usageTag(dynamic app, BankQuestionItem q) {
    return AppFocusableAction(
      onTap: () => _showUsages(q),
      hoverHighlight: true,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      semanticLabel: '查看引用过 ${q.usageCount} 次的任务',
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: app.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.link, size: 12, color: app.onSecondaryContainer),
            const SizedBox(width: 4),
            Text(
              '用过 ${q.usageCount} 次',
              style: AppTheme.textOf(context).labelSmall?.copyWith(
                    color: app.onSecondaryContainer,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 选中题目后出现的操作区（卡片底部，随页面滚动）。
  ///
  /// 用 Wrap 而非 Row+Expanded：`ShadButton` 内部是 `Row(mainAxisSize: min)`，
  /// 被父级压到窄于内容宽度时**不会收缩文字**，直接 RenderFlex overflow
  ///（「用这些题生成任务」在窄分屏下实测溢出 9px）。Wrap 让按钮保持自然宽度、
  /// 空间不足时整块换行，任何窗口宽度都不会压出溢出。
  Widget _buildActionFooter(dynamic app, bool busy) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 归档与删除并排：被任务引用的题删不掉，家长只能堆着——归档就是给
        // 这种情况的出口，所以它必须和删除一样显眼，且可恢复（ADR-0053 P2）。
        ShadButton.outline(
          onPressed: busy ? null : () => _archiveSelected(true),
          leading: const Icon(LucideIcons.archive, size: 16),
          child: Text('归档选中 (${_selectedIds.length})'),
        ),
        if (_archived != 'active')
          ShadButton.outline(
            onPressed: busy ? null : () => _archiveSelected(false),
            leading: const Icon(LucideIcons.archiveRestore, size: 16),
            child: Text('恢复选中 (${_selectedIds.length})'),
          ),
        ShadButton.outline(
          onPressed: busy ? null : _deleteSelected,
          leading: const Icon(LucideIcons.trash2, size: 16),
          child: Text('删除选中 (${_selectedIds.length})'),
        ),
        // 打印导出（ADR-0052）：复用本页多选，出口与删除/组卷并排。
        ShadButton.outline(
          onPressed: busy ? null : _exportSelected,
          leading: const Icon(LucideIcons.printer, size: 16),
          child: Text('导出打印 (${_selectedIds.length})'),
        ),
        ShadButton(
          onPressed: busy ? null : _generate,
          leading: const Icon(LucideIcons.filePlus, size: 16),
          child: Text('用这些题生成任务 (${_selectedIds.length})'),
        ),
        ShadButton.outline(
          onPressed: busy ? null : _addToDraft,
          leading: const Icon(LucideIcons.folderPlus, size: 16),
          child: const Text('加入已有草稿'),
        ),
      ],
    );
  }
}

