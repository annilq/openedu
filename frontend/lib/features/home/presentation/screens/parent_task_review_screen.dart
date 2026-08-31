import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../providers/parent_task_review_notifier.dart';

/// 家长草稿审核页（R-Q1=c / R-Q3 / R-Q4 / R-Q5=b）。
///
/// 入口：ParentTaskFormView 生成成功后跳转。
/// 动作：单题/批量加入题库、删除、单题/整卷重生成、题干/选项/答案/解析
/// 内联编辑、锁定确认、派发、作废。
class ParentTaskReviewScreen extends ConsumerStatefulWidget {
  final TaskModel task;

  /// 派发时若创建时已经选好娃娃则直接绑定，否则弹窗选择。
  final String? defaultChildId;

  /// 返回 Home（Overview）或派发给娃娃后跳 PracticeScreen 预览。
  final VoidCallback onBackToHome;
  final void Function(TaskModel task)? onNavigateToPractice;

  const ParentTaskReviewScreen({
    super.key,
    required this.task,
    this.defaultChildId,
    required this.onBackToHome,
    this.onNavigateToPractice,
  });

  @override
  ConsumerState<ParentTaskReviewScreen> createState() =>
      _ParentTaskReviewScreenState();
}

class _ParentTaskReviewScreenState
    extends ConsumerState<ParentTaskReviewScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(parentTaskReviewProvider(widget.task));
    final app = AppTheme.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: app.surfaceContainerLowest,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: app.surfaceContainerLowest,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: widget.onBackToHome,
          child: const Icon(LucideIcons.arrowLeft, size: 22),
        ),
        middle: const Text('草稿审核'),
        trailing: state is ReviewLoaded
            ? _buildActionBar(state.task, app)
            : null,
      ),
      child: switch (state) {
        ReviewLoading() => const AppLoading(),
        ReviewError(:final message) =>
          AppError(message: message, onRetry: () {
            ref
                .read(parentTaskReviewProvider(widget.task).notifier)
                .load(widget.task.id);
          }),
        ReviewLoaded(task: final task) => _buildBody(task),
      },
    );
  }

  // ============ 顶部操作栏 ============

  Widget _buildActionBar(TaskModel task, dynamic app) {
    if (task.isDraft) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 题库组卷任务 specs 为空，无 AI 生成规格，故不展示「整卷重生成」
          if (task.specs.isNotEmpty)
            ShadButton.outline(
              onPressed: () => _onRegenerateAll(task.id),
              leading: const Icon(LucideIcons.rotateCw, size: 16),
              child: const Text('整卷重生成'),
            ),
          const SizedBox(width: AppSpacing.sm),
          ShadButton.outline(
            onPressed: task.promotedCount == task.questions.length
                ? null
                : () => _onPromoteAll(task.id),
            leading: const Icon(LucideIcons.database, size: 16),
            child: Text('一键加入题库 '
                '(${task.promotedCount}/${task.questions.length})'),
          ),
          const SizedBox(width: AppSpacing.sm),
          ShadButton.destructive(
            onPressed: () => _onDiscard(task.id),
            leading: const Icon(LucideIcons.trash2, size: 16),
            child: const Text('作废'),
          ),
          const SizedBox(width: AppSpacing.md),
          ShadButton(
            onPressed: task.questions.isEmpty ? null : () => _onConfirm(task),
            size: ShadButtonSize.lg,
            leading: const Icon(LucideIcons.lock, size: 18),
            child: const Text('锁定并派发'),
          ),
        ],
      );
    }
    if (task.isReady) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.defaultChildId != null)
            ShadButton(
              onPressed: () => _onAssign(task, widget.defaultChildId!),
              size: ShadButtonSize.lg,
              leading: const Icon(LucideIcons.send, size: 18),
              child: const Text('派发任务'),
            )
          else
            ShadButton(
              onPressed: () {
                AppToast.show(context, '请在首页选择娃娃后再派发');
              },
              size: ShadButtonSize.lg,
              leading: const Icon(LucideIcons.send, size: 18),
              child: const Text('派发'),
            ),
        ],
      );
    }
    if (task.isAssigned) {
      return ShadButton.secondary(
        onPressed: widget.onNavigateToPractice == null
            ? null
            : () => widget.onNavigateToPractice!(task),
        leading: const Icon(LucideIcons.eye, size: 18),
        child: const Text('查看练习'),
      );
    }
    return ShadButton.secondary(
      onPressed: widget.onBackToHome,
      child: const Text('返回首页'),
    );
  }

  // ============ Body ============

  Widget _buildBody(TaskModel task) {
    final app = AppTheme.colorsOf(context);
    final total = task.questions.length;
    final promoted = task.promotedCount;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSummary(task, app, promoted, total),
              const SizedBox(height: AppSpacing.xl2),
              if (task.questions.isEmpty)
                _EmptyHint(onRegen: () => _onRegenerateAll(task.id))
              else
                ...List.generate(task.questions.length, (i) {
                  final q = task.questions[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: _QuestionCard(
                      key: ValueKey(q.id),
                      index: i + 1,
                      question: q,
                      isDraft: task.isDraft,
                      onPromote: () =>
                          _onPromoteOne(task.id, q.id),
                      onDelete: task.questions.length <= 1
                          ? null
                          : () => _onDelete(task.id, q.id),
                      onRegenerate: () =>
                          _onRegenerateOne(task.id, q.id),
                      onEdit: (edits) =>
                          _onEdit(task.id, q.id, edits),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(TaskModel task, dynamic app, int promoted, int total) {
    final statusChip = switch (task.status) {
      'draft' => ('草稿', app.tertiary, app.onTertiary),
      'ready' => ('已锁定', app.primary, app.onPrimary),
      'assigned' => ('已派发', app.secondary, app.onSecondary),
      'done' => ('已完成', app.onSurface, app.surface),
      _ => ('未知', app.outlineVariant, app.outline),
    } as (String, Color, Color);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: app.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: app.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: AppTheme.textOf(context).headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: statusChip.$2,
                  borderRadius: BorderRadius.circular(AppRadius.bubble),
                ),
                child: Text(
                  statusChip.$1,
                  style: AppTheme.textOf(context).labelMedium?.copyWith(
                        color: statusChip.$3,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xl2,
            runSpacing: AppSpacing.sm,
            children: [
              _Stat(
                label: '题目数',
                value: total.toString(),
                icon: LucideIcons.fileQuestion,
              ),
              _Stat(
                label: '已入题库',
                value: '$promoted / $total',
                icon: LucideIcons.database,
                tone: promoted == total
                    ? app.primary
                    : app.onSurfaceVariant,
              ),
              if (task.specs.isNotEmpty)
                _SpecsSummary(specs: task.specs),
            ],
          ),
        ],
      ),
    );
  }

  // ============ Actions ============

  Future<void> _onPromoteOne(String taskId, String tqId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .promoteOne(taskId: taskId, tqId: tqId);
      if (!mounted) return;
      AppToast.show(context, '已加入题库');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onPromoteAll(String taskId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .promoteAll(taskId);
      if (!mounted) return;
      AppToast.show(context, '全部加入题库成功');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onDelete(String taskId, String tqId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .removeOne(taskId: taskId, tqId: tqId);
      if (!mounted) return;
      AppToast.show(context, '已删除');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onRegenerateOne(String taskId, String tqId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .regenerateOne(taskId: taskId, tqId: tqId);
      if (!mounted) return;
      AppToast.show(context, '已生成新题目');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onRegenerateAll(String taskId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .regenerateAll(taskId);
      if (!mounted) return;
      AppToast.show(context, '整卷已按原规格重生成');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onEdit(
      String taskId, String tqId, Map<String, dynamic> edits) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .editOne(taskId: taskId, tqId: tqId, edits: edits);
      if (!mounted) return;
      AppToast.show(context, '题目已更新');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onConfirm(TaskModel task) async {
    try {
      final confirmed = await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .confirm(task.id);
      if (!mounted) return;
      AppToast.show(context, '已锁定成卷');
      // 若家长预选了娃娃（创建时就选好），自动下一步派发
      final childId = widget.defaultChildId ?? confirmed.childId;
      if (childId != null) {
        await _onAssign(confirmed, childId);
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onAssign(TaskModel task, String childId) async {
    try {
      final assigned = await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .assign(taskId: task.id, childId: childId);
      if (!mounted) return;
      AppToast.show(context, '已派发给娃娃');
      widget.onNavigateToPractice?.call(assigned);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onDiscard(String taskId) async {
    final confirmed = await _showConfirmDialog(
      context: context,
      title: '确定作废草稿?',
      desc: '作废后已加入题库的题目会一并删除，且无法恢复。',
      confirmText: '作废',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task).notifier)
          .discard(taskId);
      if (!mounted) return;
      AppToast.show(context, '草稿已作废');
      widget.onBackToHome();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }
}

// ============ Sub widgets ============

class _QuestionCard extends ConsumerStatefulWidget {
  final int index;
  final QuestionModel question;
  final bool isDraft;
  final Future<void> Function()? onPromote;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onRegenerate;
  final Future<void> Function(Map<String, dynamic> edits)? onEdit;

  const _QuestionCard({
    super.key,
    required this.index,
    required this.question,
    required this.isDraft,
    this.onPromote,
    this.onDelete,
    this.onRegenerate,
    this.onEdit,
  });

  @override
  ConsumerState<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<_QuestionCard> {
  final _stemCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  final _explanationCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [];

  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _syncCtrls(widget.question);
  }

  @override
  void didUpdateWidget(covariant _QuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question != widget.question && !_editing) {
      _syncCtrls(widget.question);
    }
  }

  void _syncCtrls(QuestionModel q) {
    _stemCtrl.text = q.stem;
    _answerCtrl.text = q.answer ?? '';
    _explanationCtrl.text = q.explanation;
    _optionCtrls
      ..forEach((c) => c.dispose())
      ..clear();
    final opts = q.options ?? const <String>[];
    for (final o in opts) {
      _optionCtrls.add(TextEditingController(text: o));
    }
  }

  @override
  void dispose() {
    _stemCtrl.dispose();
    _answerCtrl.dispose();
    _explanationCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final app = AppTheme.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: app.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: app.outline),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(q, app),
          const SizedBox(height: AppSpacing.md),
          _editing ? _buildEditForm(q) : _buildReadonly(q),
          const SizedBox(height: AppSpacing.lg),
          if (widget.isDraft) _buildActions(q, app),
        ],
      ),
    );
  }

  Widget _buildHeader(QuestionModel q, dynamic app) {
    final inBank = q.inQuestionBank;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: app.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.bubble),
          ),
          alignment: Alignment.center,
          child: Text(
            '${widget.index}',
            style: AppTheme.textOf(context).labelLarge?.copyWith(
                  color: app.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: app.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(q.subject,
              style: AppTheme.textOf(context).labelSmall),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '${q.grade}年级·${q.knowledgePoint}·${_qtypeLabel(q.qtype)}·${_diffLabel(q.difficulty)}',
          style: AppTheme.textOf(context).bodySmall?.copyWith(
                color: app.onSurfaceVariant,
              ),
        ),
        const Spacer(),
        if (inBank)
          Icon(
            LucideIcons.checkCircle2,
            size: 18,
            color: app.primary,
          )
        else
          Icon(
            LucideIcons.circleDashed,
            size: 18,
            color: app.onSurfaceVariant,
          ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          inBank ? '已入题库' : '未入题库',
          style: AppTheme.textOf(context).labelMedium?.copyWith(
                color: inBank ? app.primary : app.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildReadonly(QuestionModel q) {
    final app = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q.stem,
          style: AppTheme.textOf(context).bodyLarge?.copyWith(
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
        ),
        if (q.options != null && q.options!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Column(
              children: q.options!.asMap().entries.map((e) {
                final i = e.key;
                final label =
                    String.fromCharCode(65 + i); // A B C D ...
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: app.surfaceContainerHigh,
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(label,
                            style: AppTheme.textOf(context).labelMedium),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                          child: Text(e.value,
                              style: AppTheme.textOf(context).bodyMedium
                                  ?.copyWith(height: 1.4))),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        if (q.answer != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: app.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.bubble),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.keyRound,
                      size: 18, color: app.onPrimaryContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '答案：${q.answer!}',
                      style: AppTheme.textOf(context).bodyMedium?.copyWith(
                            color: app.onPrimaryContainer,
                            height: 1.5,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (q.explanation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.lightbulb,
                    size: 18, color: app.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '解析：${q.explanation}',
                    style: AppTheme.textOf(context).bodyMedium?.copyWith(
                          color: app.onSurfaceVariant,
                          height: 1.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEditForm(QuestionModel q) {
    final app = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('题干（R-Q4：仅此处/选项/答案/解析允许修改）'),
        ShadInput(
          controller: _stemCtrl,
          maxLines: null,
          minLines: 2,
          style: AppTheme.textOf(context).bodyLarge,
          decoration: _fieldDecoration(app),
        ),
        if (q.options != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _label('选项（可留空表示单选/填空题）'),
          ...List.generate(_optionCtrls.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    child: Text(
                      String.fromCharCode(65 + i),
                      style: AppTheme.textOf(context).labelMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ShadInput(
                      controller: _optionCtrls[i],
                      style: AppTheme.textOf(context).bodyMedium,
                      decoration: _fieldDecoration(app),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _optionCtrls.length <= 2
                        ? null
                        : () {
                            setState(() {
                              _optionCtrls[i].dispose();
                              _optionCtrls.removeAt(i);
                            });
                          },
                    child: Icon(LucideIcons.minus,
                        size: 18,
                        color: _optionCtrls.length <= 2
                            ? app.outline
                            : app.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              height: 36,
              onPressed: () {
                setState(() {
                  _optionCtrls.add(TextEditingController());
                });
              },
              leading: const Icon(LucideIcons.plus, size: 16),
              child: const Text('添加选项'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _label('参考答案'),
        ShadInput(
          controller: _answerCtrl,
          style: AppTheme.textOf(context).bodyLarge,
          decoration: _fieldDecoration(app),
        ),
        const SizedBox(height: AppSpacing.lg),
        _label('解析'),
        ShadInput(
          controller: _explanationCtrl,
          minLines: 2,
          maxLines: null,
          style: AppTheme.textOf(context).bodyMedium,
          decoration: _fieldDecoration(app),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            ShadButton.secondary(
              onPressed: () {
                _syncCtrls(widget.question);
                setState(() => _editing = false);
              },
              child: const Text('取消'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ShadButton(
              onPressed: _submitEdits,
              leading: const Icon(LucideIcons.check, size: 16),
              child: const Text('保存修改'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submitEdits() async {
    final opts = widget.question.options != null
        ? _optionCtrls.map((c) => c.text).toList()
        : null;
    final edits = widget.question.editablePatch(
      stem: _stemCtrl.text.trim(),
      options: opts,
      answer: _answerCtrl.text.trim(),
      explanation: _explanationCtrl.text.trim(),
    );
    if (edits.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    try {
      await widget.onEdit?.call(edits);
      if (mounted) setState(() => _editing = false);
    } catch (_) {
      // toast by caller
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(t,
            style: AppTheme.textOf(context).labelMedium?.copyWith(
                  color: AppTheme.colorsOf(context).onSurfaceVariant,
                )),
      );

  ShadDecoration _fieldDecoration(dynamic app) => ShadDecoration(
        color: app.surfaceContainerLow,
        border: ShadBorder.all(
          color: app.outline,
          width: 1,
          radius: BorderRadius.circular(AppRadius.bubble),
        ),
        focusedBorder: ShadBorder.all(
          color: app.primary,
          width: 1.2,
          radius: BorderRadius.circular(AppRadius.bubble),
        ),
      );

  Widget _buildActions(QuestionModel q, dynamic app) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        ShadButton.outline(
          height: 36,
          onPressed: q.inQuestionBank ? null : widget.onPromote,
          leading: const Icon(LucideIcons.database, size: 16),
          child: Text(q.inQuestionBank ? '已入题库' : '加入题库'),
        ),
        ShadButton.outline(
          height: 36,
          onPressed: _editing
              ? null
              : () => setState(() => _editing = true),
          leading: const Icon(LucideIcons.pencil, size: 16),
          child: Text(_editing ? '编辑中…' : '编辑题目'),
        ),
        ShadButton.outline(
          height: 36,
          onPressed: widget.onRegenerate,
          leading: const Icon(LucideIcons.rotateCw, size: 16),
          child: const Text('换一题'),
        ),
        ShadButton.destructive(
          height: 36,
          onPressed: widget.onDelete,
          leading: const Icon(LucideIcons.trash2, size: 16),
          child: const Text('删除'),
        ),
      ],
    );
  }

  String _qtypeLabel(String t) => switch (t) {
        'calc' => '计算题',
        'choice' => '选择题',
        'fill' => '填空题',
        'word' => '应用题',
        _ => t,
      };

  String _diffLabel(String d) => switch (d) {
        'easy' => '易',
        'medium' => '中',
        'hard' => '难',
        _ => d,
      };
}

class _EmptyHint extends StatelessWidget {
  final VoidCallback? onRegen;
  const _EmptyHint({this.onRegen});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl3),
      decoration: BoxDecoration(
        color: app.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: app.outline),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.inbox, size: 48, color: app.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text('草稿暂未包含任何题目',
              style: AppTheme.textOf(context).titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('点击「整卷重生成」按原规格重新出题',
              style: AppTheme.textOf(context).bodyMedium
                  ?.copyWith(color: app.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          ShadButton(
            onPressed: onRegen,
            leading: const Icon(LucideIcons.rotateCw, size: 18),
            child: const Text('整卷重生成'),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? tone;
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final color = tone ?? app.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$value  ',
                style: AppTheme.textOf(context).titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: app.onSurface,
                    ),
              ),
              TextSpan(
                text: label,
                style: AppTheme.textOf(context).bodySmall
                    ?.copyWith(color: app.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpecsSummary extends StatelessWidget {
  final List<TaskSpecModel> specs;
  const _SpecsSummary({required this.specs});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.listChecks, size: 18, color: app.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.45),
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: specs.map((s) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: app.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${s.subject}·${s.grade}·${s.knowledgePoint} x${s.count}',
                  style: AppTheme.textOf(context).bodySmall,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ============ Confirm Dialog ============

Future<bool?> _showConfirmDialog({
  required BuildContext context,
  required String title,
  required String desc,
  String confirmText = '确定',
  bool destructive = false,
}) async {
  return showShadDialog<bool>(
    context: context,
    builder: (ctx) {
      final app = AppTheme.colorsOf(ctx);
      return ShadDialog.alert(
        title: Text(title),
        description: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(desc),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          if (destructive)
            ShadButton.destructive(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmText),
            )
          else
            ShadButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmText),
            ),
        ],
        backgroundColor: app.surface,
      );
    },
  );
}
