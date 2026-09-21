import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/question_labels.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../../shared/widgets/stream_reasoning_panel.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_tags.dart';

/// 草稿审核页的单题卡片：只读展示 / 内联编辑 / 单题动作（入库、删除、换一题）。
///
/// 从 `parent_task_review_screen.dart` 拆出——原文件 1204 行里有一半是这张卡片
/// （含自己的编辑表单状态），把「页面编排」与「一题怎么渲染/编辑」混在一起。
class ParentQuestionCard extends ConsumerStatefulWidget {
  final int index;
  final QuestionModel question;
  final bool isDraft;

  /// 该卡片正在执行一个单题动作（删除/编辑保存/换一题/加入题库）。
  ///
  /// 期间按钮全部禁用并显示 spinner。此前没有这个标记：换一题是一次同步 LLM
  /// 调用，按钮点了长时间没任何反馈，家长连点会并发多个请求。
  final bool busy;

  /// 该卡片正被「换一题」重生成时，模型实时产出的推理文本（THINKING 帧累加）。
  ///
  /// 仅当前卡 = busyTqId 时由父级传入（整卷重生成的 liveText 走顶部进度区），
  /// 非空即在该卡内展示一个「模型思考中」流式面板，替代原本只能干等「处理中…」三字的体验。
  final String liveText;

  final Future<void> Function()? onPromote;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onRegenerate;
  final Future<void> Function(Map<String, dynamic> edits)? onEdit;

  const ParentQuestionCard({
    super.key,
    required this.index,
    required this.question,
    required this.isDraft,
    this.busy = false,
    this.liveText = '',
    this.onPromote,
    this.onDelete,
    this.onRegenerate,
    this.onEdit,
  });

  @override
  ConsumerState<ParentQuestionCard> createState() => ParentQuestionCardState();
}

class ParentQuestionCardState extends ConsumerState<ParentQuestionCard> {
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
  void didUpdateWidget(covariant ParentQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // busy 期间不重灌输入框，避免覆盖用户正在编辑的内容。
    if (oldWidget.question != widget.question && !_editing && !widget.busy) {
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
    return PopIn(
      key: ValueKey(widget.index),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(q, app),
            const SizedBox(height: AppSpacing.md),
            _editing ? _buildEditForm(q) : _buildReadonly(q),
            // 换一题进行中：在卡片内直接展示模型实时推理文本，而不是让家长只能看到
            // 「处理中…」三个字干等十几秒。整卷重生成的 liveText 走顶部进度区，这里只渲染单题的。
            if (!_editing && widget.liveText.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              StreamReasoningPanel(
                index: null,
                label: '',
                reasoning: widget.liveText,
                streaming: true,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (widget.isDraft) _buildActions(q, app),
          ],
        ),
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
            color: AppBrutal.violet,
            borderRadius: BorderRadius.circular(AppRadius.bubble),
            // 题号徽标 = 密集小色块档（[AppElevation.borderWidthSm]），
            // 见 AppElevation 的三档口径。
            border: Border.all(
              color: AppBrutal.ink,
              width: AppElevation.borderWidthSm,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '${widget.index}',
            style: AppTheme.textOf(context).labelLarge?.copyWith(
                  color: AppBrutal.onDark,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        AppTags.subject(SubjectAccent.fromName(q.subject), label: q.subject),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '${q.grade}年级·${q.knowledgePoint}·${qtypeLabelFull(q.qtype)}·${_diffLabel(q.difficulty)}',
          style: AppTheme.textOf(context).bodySmall?.copyWith(
                color: app.onSurfaceVariant,
              ),
        ),
        const Spacer(),
        if (inBank)
          AppTags.success('已入题库')
        else
          AppTags.normal('未入题库'),
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
                final label = String.fromCharCode(65 + i); // A B C D ...
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
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(label,
                            style: AppTheme.textOf(context).labelMedium),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                          child: Text(e.value,
                              style: AppTheme.textOf(context)
                                  .bodyMedium
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
                      // shadcn 的 EditableText 默认 textAlignVertical=top（文字偏上），
                      // 用 forceStrutHeight 把行高撑满编辑盒（controlH - 4）使字形居中。
                      strutStyle: AppControl.inputStrut(
                          context, AppTheme.textOf(context).bodyMedium),
                      constraints: AppControl.inputConstraintsOf(context),
                      decoration: _fieldDecoration(app),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // 命中区走标准档 → 与同行输入框同高（CupertinoButton 的默认
                  // 44×44 minSize 会把这一行撑高）。禁用态淡色由组件统一给。
                  AppIconAction(
                    icon: LucideIcons.minus,
                    semanticLabel: '删除第 ${i + 1} 个选项',
                    onPressed: _optionCtrls.length <= 2
                        ? null
                        : () {
                            setState(() {
                              _optionCtrls[i].dispose();
                              _optionCtrls.removeAt(i);
                            });
                          },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
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
          // shadcn 的 EditableText 默认 textAlignVertical=top（文字偏上），
          // 用 forceStrutHeight 把行高撑满编辑盒（controlH - 4）使字形居中。
          strutStyle:
              AppControl.inputStrut(context, AppTheme.textOf(context).bodyLarge),
          constraints: AppControl.inputConstraintsOf(context),
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
              onPressed: widget.busy
                  ? null
                  : () {
                      _syncCtrls(widget.question);
                      setState(() => _editing = false);
                    },
              child: const Text('取消'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ShadButton(
              onPressed: widget.busy ? null : _submitEdits,
              leading: const Icon(LucideIcons.check, size: 16),
              child: Text(widget.busy ? '保存中…' : '保存修改'),
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
    final busy = widget.busy;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ShadButton.outline(
          
          onPressed: busy || q.inQuestionBank ? null : widget.onPromote,
          leading: const Icon(LucideIcons.database, size: 16),
          child: Text(q.inQuestionBank ? '已入题库' : '加入题库'),
        ),
        ShadButton.outline(
          
          onPressed: busy || _editing ? null : () => setState(() => _editing = true),
          leading: const Icon(LucideIcons.pencil, size: 16),
          child: Text(_editing ? '编辑中…' : '编辑题目'),
        ),
        ShadButton.outline(
          
          onPressed: busy ? null : widget.onRegenerate,
          leading: const Icon(LucideIcons.rotateCw, size: 16),
          child: const Text('换一题'),
        ),
        ShadButton.destructive(
          
          onPressed: busy ? null : widget.onDelete,
          leading: const Icon(LucideIcons.trash2, size: 16),
          child: const Text('删除'),
        ),
        if (busy) ...[
          const SizedBox(width: AppSpacing.sm),
          // 与 AppLoading 同款：Lucide 图标转圈，不引入 Material 组件
          // （整棵 widget 树基于 ShadApp/CupertinoApp，无 Material 祖先）。
          Icon(LucideIcons.loaderCircle, size: 16, color: app.primary)
              .animate(onPlay: (c) => c.repeat())
              .rotate(duration: const Duration(milliseconds: 900)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '处理中…',
            style: AppTheme.textOf(context).bodySmall?.copyWith(
                  color: app.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }

  String _diffLabel(String d) => switch (d) {
        'easy' => '易',
        'medium' => '中',
        'hard' => '难',
        _ => d,
      };
}

// ============ 流式实时文本面板 ============
// 复用 shared/widgets/stream_reasoning_panel.dart 的 StreamReasoningPanel
// （「换一题」与整卷重生成共用同一渲染 seam，见 DRY 收敛说明）。
