import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_toast.dart';
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

class _ParentQuestionBankViewState extends ConsumerState<ParentQuestionBankView> {
  static const List<String> _subjects = [
    '数学', '语文', '英语', '科学', '道法', '历史', '地理', '生物', '物理', '化学'
  ];
  static const List<String> _qtypes = ['calc', 'fill', 'choice', 'open'];
  static const List<String> _qtypeLabels = ['计算', '填空', '选择', '应用'];

  String _selectedSubject = ''; // '' = 全部
  String _selectedQtype = 'all'; // 'all' = 全部
  int _gradeSegment = -1; // -1 = 全部
  final Set<String> _selectedIds = {};
  final TextEditingController _keywordCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController(text: '题库组卷');
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(questionBankNotifierProvider.notifier).load();
    });
  }

  @override
  void dispose() {
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
      keyword: _keywordCtrl.text.trim().isEmpty ? null : _keywordCtrl.text.trim(),
    );
  }

  void _onKeywordChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  void _toggle(String id) =>
      setState(() => _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id));

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
      title: _titleCtrl.text.trim().isEmpty ? '题库组卷' : _titleCtrl.text.trim(),
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
              return GestureDetector(
                onTap: () => Navigator.of(ctx).pop(t.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: app.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, style: AppTheme.textOf(ctx).bodyMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${t.questions.length} 题 · ${_statusLabel(t.status)}',
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

  String _statusLabel(String s) => switch (s) {
        'draft' => '草稿',
        'ready' => '已锁定',
        'assigned' => '已派发',
        'done' => '已完成',
        _ => s,
      };

  String _qtypeLabel(String t) => switch (t) {
        'calc' => '计算题',
        'choice' => '选择题',
        'fill' => '填空题',
        'open' => '应用题',
        _ => t,
      };

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
      } else if (next is BankActionError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) AppToast.error(context, next.message);
        });
      }
    });

    return Column(
      children: [
        _buildToolbar(app),
        Expanded(child: _buildBody(state, app)),
        if (_selectedIds.isNotEmpty)
          _buildActionBar(app, busy),
      ],
    );
  }

  Widget _buildToolbar(dynamic app) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: app.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('题库', style: AppTheme.textOf(context).headlineSmall),
          const SizedBox(height: AppSpacing.md),
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
        ],
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

  Widget _buildBody(BankState state, dynamic app) {
    if (state is BankLoading || state is BankIdle) {
      return const AppLoading();
    }
    if (state is BankError) {
      return AppError(message: state.message, onRetry: _reload);
    }
    if (state is BankActionLoading) {
      return const AppLoading();
    }
    final data = (state as BankLoaded).data;
    if (data.items.isEmpty) {
      return _EmptyHint(onReload: _reload);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl2),
      itemCount: data.items.length,
      itemBuilder: (_, i) => _buildItem(data.items[i], app),
    );
  }

  Widget _buildItem(BankQuestionItem q, dynamic app) {
    final selected = _selectedIds.contains(q.id);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: app.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: selected ? app.primary : app.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: GestureDetector(
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
                        _tag(app, _qtypeLabel(q.qtype)),
                        if (q.usageCount > 0)
                          _tag(app, '用过 ${q.usageCount} 次',
                              tone: app.onSurfaceVariant),
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
      ),
    );
  }

  Widget _tag(dynamic app, String text, {Color? tone}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
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

  Widget _buildActionBar(dynamic app, bool busy) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: app.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ShadButton(
              onPressed: busy ? null : _generate,
              leading: const Icon(LucideIcons.filePlus, size: 16),
              child: Text('用这些题生成任务 (${_selectedIds.length})'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ShadButton.outline(
            onPressed: busy ? null : _addToDraft,
            leading: const Icon(LucideIcons.folderPlus, size: 16),
            child: const Text('加入已有草稿'),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final VoidCallback onReload;
  const _EmptyHint({required this.onReload});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl3),
      child: Column(
        children: [
          Icon(LucideIcons.library, size: 48, color: app.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text('题库还是空的', style: AppTheme.textOf(context).titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('去「布置任务」生成题目并加入题库，这里就会积累你的专属题集',
              style: AppTheme.textOf(context)
                  .bodyMedium
                  ?.copyWith(color: app.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          ShadButton(onPressed: onReload, child: const Text('刷新')),
        ],
      ),
    );
  }
}
