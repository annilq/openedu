import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// LucideIcons 由 shadcn_ui 再导出。
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_model_selector.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../children/domain/providers/children_provider.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../../../tutor/presentation/providers/models_notifier.dart';
import '../../providers/home_notifier.dart';
import '../../providers/selected_child_provider.dart';
import '../../../../review/presentation/providers/review_notifier.dart';

/// 布置练习任务右栏：多学科行表单 + 一键均分 + 生成（ADR-0004）。
/// R3：生成成功后不直接跳娃娃练习页，回调 `onNavigateToReview` 进草稿审核页。
class ParentTaskFormView extends ConsumerStatefulWidget {
  final void Function(TaskModel task) onNavigateToReview;
  const ParentTaskFormView({super.key, required this.onNavigateToReview});

  @override
  ConsumerState<ParentTaskFormView> createState() => _ParentTaskFormViewState();
}

/// 内置学科选项（覆盖小学至初中 K9 全学科）。
///
/// 任务建接口（[taskGenNotifierProvider]）对 subject 仅原样存储、不做白名单校验，
/// 故此处可放开到全学科；tutor 答疑学科白名单受后端 `SUBJECTS` 约束，不在此列。
const List<String> _kSubjects = <String>[
  '语文',
  '数学',
  '英语',
  '道德与法治',
  '科学',
  '历史',
  '地理',
  '物理',
  '化学',
  '生物',
  '音乐',
  '美术',
  '体育与健康',
  '信息技术',
];

/// 一行学科规格（学科 + 知识点 + 题型 + 难度 + 题量 + 年级）。
class _SpecRow {
  String subject;
  final TextEditingController knowledgePoint;
  final TextEditingController count;
  String qtype = 'calc';
  // null = 继承当前选中娃娃的年级；非 null = 家长手动覆盖。
  int? grade;

  _SpecRow({
    String? subject,
    String? knowledgePoint,
    String? count,
  })  : subject = subject ?? '数学',
        knowledgePoint =
            TextEditingController(text: knowledgePoint ?? '两位数加减法'),
        count = TextEditingController(text: count ?? '5');

  void dispose() {
    knowledgePoint.dispose();
    count.dispose();
  }

  TaskSpecModel toSpec(int defaultGrade) => TaskSpecModel(
        subject: subject,
        // 未手动指定时继承当前选中娃娃年级；娃娃年级维持家长手动维护（ADR-0005 修订）。
        grade: grade ?? defaultGrade,
        knowledgePoint: knowledgePoint.text,
        qtype: qtype,
        count: int.tryParse(count.text) ?? 1,
      );
}

class _ParentTaskFormViewState extends ConsumerState<ParentTaskFormView> {
  final List<_SpecRow> _rows = [_SpecRow()];
  final _totalCtrl = TextEditingController(text: '10');
  final _titleCtrl = TextEditingController(text: '今日练习');

  // 兴趣题模式（WF-4）：开=聚焦所选兴趣主题；关=后端自动轻融入娃娃画像。
  bool _useInterestMode = false;
  final Set<String> _focusThemes = {};

  // 多模型（票据 08）：出题时自选模型；null = 后端自动（默认/全局）。
  String? _modelId;

  @override
  void initState() {
    super.initState();
    // 预拉取可选模型列表，供模型选择器展示（仅家长可见自定义模型）。
    Future.microtask(
      () => ref.read(modelsNotifierProvider.notifier).load(),
    );
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _totalCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_SpecRow(
        subject: '语文',
        knowledgePoint: '字词积累',
      )));

  void _removeRow(int i) => setState(() {
        if (_rows.length > 1) {
          _rows[i].dispose();
          _rows.removeAt(i);
        }
      });

  /// 一键均分（ADR-0004 D5）：总题数按当前行数等分，余数给前几行。
  void _evenSplit() {
    final total = int.tryParse(_totalCtrl.text) ?? 10;
    final n = _rows.length;
    if (n == 0) return;
    final base = total ~/ n;
    final extra = total % n;
    setState(() {
      for (var i = 0; i < n; i++) {
        _rows[i].count.text = (base + (i < extra ? 1 : 0)).toString();
      }
    });
  }

  List<TaskSpecModel> _currentSpecs(SelectedChild selected) =>
      _rows.map((r) => r.toSpec(selected.grade)).toList();

  /// 兴趣题模式（WF-4）：开启且至少选一个主题才下传聚焦主题；否则 null = 后端自动轻融入。
  List<String>? _currentFocus() =>
      _useInterestMode && _focusThemes.isNotEmpty ? _focusThemes.toList() : null;

  void _generate() {
    final selected = ref.read(selectedChildProvider);
    if (selected == null) {
      AppToast.show(context, '请先在侧栏选择娃娃');
      return;
    }
    final specs = _currentSpecs(selected);
    if (specs.any((s) => s.subject.isEmpty || s.knowledgePoint.isEmpty)) {
      AppToast.show(context, '学科与知识点不能为空');
      return;
    }
    if (specs.any((s) => s.count < 1)) {
      AppToast.show(context, '每行题数至少为 1');
      return;
    }
    // 生成任务：先流式逐题渲染题卡（消除真实模型超时），流结束后再落库为草稿。
    ref.read(taskGenNotifierProvider.notifier).generate(
          childId: selected.id,
          title: _titleCtrl.text,
          specs: specs,
          focusInterest: _currentFocus(),
          model: _modelId,
        );
  }

  void _preview() {
    final selected = ref.read(selectedChildProvider);
    if (selected == null) {
      AppToast.show(context, '请先在侧栏选择娃娃');
      return;
    }
    final specs = _currentSpecs(selected);
    if (specs.any((s) => s.subject.isEmpty || s.knowledgePoint.isEmpty)) {
      AppToast.show(context, '学科与知识点不能为空');
      return;
    }
    if (specs.any((s) => s.count < 1)) {
      AppToast.show(context, '每行题数至少为 1');
      return;
    }
    ref.read(taskGenNotifierProvider.notifier).preview(
          childId: selected.id,
          title: _titleCtrl.text,
          specs: specs,
          focusInterest: _currentFocus(),
          model: _modelId,
        );
  }

  /// 预览后「保存为任务」：直接落库已流式返回的题卡（不再二次生成）。
  void _savePreview(TaskGenPreview s) {
    final selected = ref.read(selectedChildProvider);
    if (selected == null) {
      AppToast.show(context, '请先在侧栏选择娃娃');
      return;
    }
    ref.read(taskGenNotifierProvider.notifier).savePreview(
          childId: selected.id,
          title: _titleCtrl.text,
          specs: _currentSpecs(selected),
          questions: s.questions,
          focusInterest: _currentFocus(),
          model: _modelId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final genState = ref.watch(taskGenNotifierProvider);

    ref.listen<TaskGenState>(taskGenNotifierProvider, (prev, next) {
      // 推迟到下一帧：避免在 build 阶段同步弹 toast + 跳转，
      // 导致 widget tree 在 shadcn_ui toast SlideEffect 动画中途销毁，
      // padding 计算拿到 NaN 触发 isNonNegative 断言。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next is TaskGenSuccess) {
          AppToast.show(context, '已生成 ${next.task.questions.length} 道题');
          ref.read(taskGenNotifierProvider.notifier).reset();
          final selected = ref.read(selectedChildProvider);
          if (selected != null) {
            ref.read(progressNotifierProvider.notifier).load(selected.id);
            ref.read(masteryNotifierProvider.notifier).load(selected.id);
            ref
                .read(parentWrongQuestionsProvider.notifier)
                .load(childId: selected.id);
          }
          widget.onNavigateToReview(next.task);
        }
        if (next is TaskGenError) {
          AppToast.error(context, next.message);
        }
      });
    });

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
              const SectionTitle('布置练习任务'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(label: '试卷标题', controller: _titleCtrl),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              label: '总题数',
                              controller: _totalCtrl,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          CupertinoButton(
                            onPressed: _evenSplit,
                            child: const Text('一键均分'),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          CupertinoButton(
                            onPressed: _addRow,
                            child: const Text('+ 加学科'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ...List.generate(_rows.length, _buildRow),
                      const SizedBox(height: AppSpacing.xl),
                      AppModelSelector(
                        selected: _modelId,
                        onChanged: (v) => setState(() => _modelId = v),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _buildInterestSection(),
                      const SizedBox(height: AppSpacing.xl),
                      // 流式生成 / 落库期间：隐藏按钮；首张题卡到达前显示加载动画，
                      // 之后仅展示题卡（题卡逐张浮现），不重复显示 spinner。
                      _buildActionArea(genState),
                      const SizedBox(height: AppSpacing.lg),
                      if (genState is TaskGenPreview) _buildPreview(genState),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInterestSection() {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final selected = ref.watch(selectedChildProvider);
    final childState = ref.watch(childrenNotifierProvider);

    // 当前娃娃的兴趣主题（受控分类叶子 + 自由文本）。
    List<String> themes = const [];
    if (selected != null && childState is ChildrenLoaded) {
      for (final c in childState.children) {
        if (c.id == selected.id && c.interests != null) {
          themes = [...c.interests!.categories];
          if (c.interests!.freeText != null && c.interests!.freeText!.isNotEmpty) {
            themes.add(c.interests!.freeText!);
          }
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('按兴趣出题',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ShadSwitch(
              value: _useInterestMode,
              checkedTrackColor: app.primary,
              onChanged: (v) => setState(() {
                _useInterestMode = v;
                if (!v) _focusThemes.clear();
              }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _useInterestMode
              ? '开启后，题目将围绕所选兴趣主题生成情境。'
              : '关闭时，AI 会自动把娃娃画像中的兴趣轻融入题目。',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
        if (_useInterestMode) ...[
          const SizedBox(height: AppSpacing.md),
          if (themes.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: app.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.bubble),
              ),
              child: Text(
                '该娃娃尚未设置兴趣，请先去编辑娃娃资料添加兴趣标签。',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
              ),
            )
          else ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: themes
                    .map((t) => _ThemeToggle(
                          label: t,
                          selected: _focusThemes.contains(t),
                          onTap: () => setState(() {
                            if (_focusThemes.contains(t)) {
                              _focusThemes.remove(t);
                            } else {
                              _focusThemes.add(t);
                            }
                          }),
                        ))
                    .toList(),
              ),
              if (_focusThemes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text('已选 ${_focusThemes.length} 个主题，题量将在所选主题间轮询均分',
                      style: text.labelSmall?.copyWith(color: app.primary)),
                ),
            ],
        ],
      ],
    );
  }

  Widget _buildRow(int i) {
    final selected = ref.watch(selectedChildProvider);
    return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: AppPickerField<String>(
                label: '学科',
                values: _kSubjects,
                labels: _kSubjects,
                value: _rows[i].subject,
                onChanged: (v) => setState(() => _rows[i].subject = v),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: AppTextField(
                  label: '知识点', controller: _rows[i].knowledgePoint),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppPickerField<String>(
                label: '题型',
                values: const ['calc', 'fill', 'choice', 'open'],
                labels: const ['计算', '填空', '选择', '应用'],
                value: _rows[i].qtype,
                onChanged: (v) => setState(() => _rows[i].qtype = v),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppTextField(
                label: '题数',
                controller: _rows[i].count,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppPickerField<int>(
                label: '年级',
                values: List.generate(9, (j) => j + 1),
                labels: List.generate(9, (j) => '${j + 1}年级'),
                // 未手动指定时显示当前选中娃娃年级（与生成逻辑一致）。
                value: _rows[i].grade ?? selected?.grade ?? 2,
                onChanged: (v) => setState(() => _rows[i].grade = v),
              ),
            ),
            if (_rows.length > 1) ...[
              const SizedBox(width: AppSpacing.sm),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _removeRow(i),
                child: const Icon(LucideIcons.x, size: 20),
              ),
            ],
          ],
        ),
      );
}


  /// 流式生成 / 落库期间的操作区：隐藏按钮；首张题卡到达前显示加载动画，
  /// 之后仅展示题卡（题卡逐张浮现），不再重复 spinner。非忙碌态显示生成/预览按钮。
  Widget _buildActionArea(TaskGenState genState) {
    final busy = genState is TaskGenLoading ||
        (genState is TaskGenPreview && genState.streaming);
    final showSpinner =
        busy && (genState is TaskGenPreview ? genState.questions.isEmpty : true);
    if (showSpinner) {
      return const AppLoading();
    }
    if (busy) {
      // 题卡已在渲染：仅占位隐藏按钮，不显示 spinner。
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Expanded(
          child: AppPrimaryButton(label: '生成任务', onPressed: _generate),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CupertinoButton(
            onPressed: _preview,
            child: const Text('预览出题'),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(TaskGenPreview s) {
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '预览（${s.questions.length} 题'
                '${s.streaming ? ' · 生成中…' : ' · 已完成'}）',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (!s.streaming)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () =>
                    ref.read(taskGenNotifierProvider.notifier).reset(),
                child: const Text('收起'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...s.questions.asMap().entries.map(
              (e) => _PreviewCard(index: e.key + 1, q: e.value),
            ),
        if (!s.streaming && s.questions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(label: '保存为任务', onPressed: () => _savePreview(s)),
        ],
      ],
    );
  }
}



/// 兴趣出题主题芯片（WF-4）：点亮即把该主题加入 focus 轮询列表。
/// 视觉风格对齐 [interest_picker.dart] 中的 [_LeafToggle]。
class _ThemeToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 1.5 : 0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(LucideIcons.check,
                    size: 16, color: scheme.onPrimaryContainer),
              ),
            Text(label,
                style: text.labelMedium?.copyWith(
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

String _previewQtypeLabel(String qtype) => switch (qtype) {
      'calc' => '计算',
      'fill' => '填空',
      'choice' => '选择',
      'open' => '应用',
      _ => qtype,
    };

String _previewDifficultyLabel(String d) => switch (d) {
      'easy' => '简单',
      'medium' => '中等',
      'hard' => '困难',
      _ => d,
    };

/// 流式预览题卡（票据 08）：对应后端 `question` 事件，逐张浮现。
class _PreviewCard extends StatelessWidget {
  final int index;
  final QuestionPreview q;

  const _PreviewCard({required this.index, required this.q});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final options = q.options;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: app.surface,
        borderRadius: BorderRadius.circular(AppRadius.bubble),
        border: Border.all(color: app.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: app.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text('第 $index 题',
                    style: text.labelSmall?.copyWith(
                        color: app.onPrimaryContainer,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text(
                '${q.subject} · ${q.grade}年级 · ${_previewQtypeLabel(q.qtype)} · ${_previewDifficultyLabel(q.difficulty)}',
                style: text.labelSmall?.copyWith(color: app.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(q.stem, style: text.bodyMedium),
          if (options != null && options.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ...options.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${String.fromCharCode(65 + e.key)}. ${e.value}',
                      style: text.bodySmall,
                    ),
                  ),
                ),
          ],
          if (q.answer != null && q.answer!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('答案：${q.answer}',
                style: text.bodySmall?.copyWith(color: app.primary)),
          ],
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('解析：${q.explanation}',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
