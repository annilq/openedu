import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// LucideIcons 由 shadcn_ui 再导出。
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/question_labels.dart';
import '../../../../../shared/widgets/app_content_frame.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../../shared/widgets/stream_reasoning_panel.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../../../children/providers/children_provider.dart';
import '../../../../model_management/presentation/providers/models_notifier.dart';
import '../../../../model_management/presentation/widgets/model_selector.dart';
import '../../providers/home_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// 布置练习任务右栏：多学科行表单 + 一键均分 + 生成（ADR-0004）。
///
/// ADR-0056 审阅闸门：生成结束**停在生成页**等家长确认，此时题卡只在内存里、尚未落库；
/// 只有点「确认」才会 POST /tasks/from-generated。
///
/// ADR-0057：本页只渲染 state，**不承担任何收尾动作**。确认成功后的提示、重置、
/// 刷新与进草稿页全部由 `HomeScreen` 负责——本页只在「布置任务」这一个侧栏索引挂载，
/// 家长一切走就被卸载，挂在这里的收尾逻辑会连人一起消失（成功不提示、失败静默）。
class ParentTaskFormView extends ConsumerStatefulWidget {
  const ParentTaskFormView({super.key});

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
    // 隐藏「默认」选项后必须显式选模型：模型列表加载完成后，若尚未选择则回落到
    // 家长设为默认的模型（否则取列表首项），保证出题请求带有效 model 而非 null。
    ref.listenManual(modelsNotifierProvider, (prev, next) {
      if (next is! ModelsLoaded || _modelId != null) return;
      final all = next.resp.custom;
      if (all.isEmpty) return;
      String? defaultId;
      for (final m in all) {
        if (m.isDefault) {
          defaultId = m.id;
          break;
        }
      }
      defaultId ??= all.first.id;
      setState(() => _modelId = defaultId);
    });
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
  List<String>? _currentFocus() => _useInterestMode && _focusThemes.isNotEmpty
      ? _focusThemes.toList()
      : null;

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

  @override
  Widget build(BuildContext context) {
    final genState = ref.watch(taskGenNotifierProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
      child: AppContentFrame(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('布置练习任务'),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(label: '试卷标题', controller: _titleCtrl),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: '总题数',
                          controller: _totalCtrl,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      ShadButton.outline(
                      
                        onPressed: _evenSplit,
                        child: const Text('一键均分'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ShadButton.outline(
                      
                        onPressed: _addRow,
                        child: const Text('+ 加学科'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ...List.generate(_rows.length, _buildRow),
                  const SizedBox(height: AppSpacing.xl),
                  ModelSelector(
                    selected: _modelId,
                    onChanged: (v) => setState(() => _modelId = v),
                    showDefaultOption: false,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _buildInterestSection(),
                  const SizedBox(height: AppSpacing.xl),
                  // 流式生成 / 落库期间：隐藏按钮；首张题卡到达前显示加载动画，
                  // 之后仅展示题卡（题卡逐张浮现），不重复显示 spinner。
                  _buildActionArea(genState),
                  const SizedBox(height: AppSpacing.lg),
                  if (genState is TaskGenPreview || genState is TaskGenReady)
                    _buildPreview(genState),
                ],
              ),
            ),
          ],
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
          if (c.interests!.freeText != null &&
              c.interests!.freeText!.isNotEmpty) {
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
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
            child:
                AppTextField(label: '知识点', controller: _rows[i].knowledgePoint),
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
            // 与左侧字段同构对齐：字段是「label + sm 间距 + 40px 输入盒」的 Column，
            // 图标直接进 Row（crossAxisAlignment: start）会顶到 label 文字行，
            // 与输入盒错位（用户报障：删除按钮与学科信息没对齐）。用同款 label
            // 行高的空 Text 占位镜像结构——而非硬编码 top padding——字体/间距
            // 令牌变更时仍自动对齐。
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('', style: AppTheme.textOf(context).titleSmall),
                const SizedBox(height: AppSpacing.sm),
                // 同行有年级 ShadSelect（标准档 40）：图标操作也必须走标准档命中区，
                // 否则 CupertinoButton 的 44×44 默认 minSize 会把这一行撑高 4px。
                AppIconAction(
                  icon: LucideIcons.x,
                  iconSize: 20,
                  semanticLabel: '删除第 ${i + 1} 行',
                  onPressed: () => _removeRow(i),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 审阅闸门（ADR-0056）：生成结束**不自动落库、不自动跳转**，停在生成页等家长拍板。
  ///
  /// 三个出口各有明确语义：确认 = 落库为 draft 并进草稿页；重新生成 = 丢弃内存里的题卡重跑
  /// （数据库里还没有任何行，不会产生第二份草稿）；放弃 = 回空闲态（同样无需删除调用）。
  ///
  /// 并排按钮一律走 `Wrap`：窄栏（<700）下 `Row` + 固定宽会压缩 [ShadButton]
  /// 的内容盒导致 overflow（描边画在盒外，可见高 = 声明高 + 2×描边宽）。
  Widget _buildReviewGate() {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppPrimaryButton(label: '确认并进入草稿', onPressed: _confirm),
        ShadButton.outline(
          onPressed: _generate,
          leading: const Icon(LucideIcons.rotateCw, size: 16),
          child: const Text('重新生成'),
        ),
        ShadButton.outline(
          onPressed: _discard,
          leading: const Icon(LucideIcons.x, size: 16),
          child: const Text('放弃'),
        ),
      ],
    );
  }

  /// 确认：把内存里的题卡落库为 draft 任务，成功后由 [ref.listen] 跳草稿页。
  void _confirm() {
    ref.read(taskGenNotifierProvider.notifier).confirm();
  }

  /// 放弃：题卡只在内存里，丢弃即可，不需要调任何删除接口（ADR-0056）。
  void _discard() {
    ref.read(taskGenNotifierProvider.notifier).discard();
  }

  Widget _buildActionArea(TaskGenState genState) {
    // 生成结束、等待确认：优先于忙碌判定——此时不该隐藏按钮，反而必须给出口。
    if (genState is TaskGenReady) return _buildReviewGate();
    final busy = genState is TaskGenLoading ||
        (genState is TaskGenPreview && genState.streaming);
    final showSpinner = busy &&
        (genState is TaskGenPreview
            ? (genState.questions.isEmpty && genState.liveIndex < 0)
            : true);
    if (showSpinner) {
      final stage =
          genState is TaskGenPreview ? genState.stage : '';
      return AppLoading(message: stage.isEmpty ? '正在准备出题…' : stage);
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
      ],
    );
  }

  /// 预览区。[TaskGenPreview]（流式/落库中）与 [TaskGenReady]（待确认）共用同一套渲染，
  /// 后者只是「不再有流式推理区」的同构形态。
  Widget _buildPreview(TaskGenState genState) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final List<QuestionPreview> questions;
    final bool streaming;
    final List<String> failures;
    final int liveIndex;
    final String liveLabel;
    final String liveReasoning;
    final bool awaitingConfirm = genState is TaskGenReady;
    if (genState is TaskGenPreview) {
      questions = genState.questions;
      streaming = genState.streaming;
      failures = genState.failures;
      liveIndex = genState.liveIndex;
      liveLabel = genState.liveLabel;
      liveReasoning = genState.liveReasoning;
    } else {
      final r = genState as TaskGenReady;
      questions = r.questions;
      streaming = false;
      failures = r.failures;
      liveIndex = -1;
      liveLabel = '';
      liveReasoning = '';
    }
    final status = streaming
        ? '生成中…'
        : awaitingConfirm
            ? '待确认'
            : '已完成';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '预览（${questions.length} 题 · $status）',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        // 边界文案（ADR-0056）：思路不落库是设计，但若不说清楚，进入草稿页后
        // 「思路不见了」会被当成 bug 再报一次。行为与文案互相印证。
        if (questions.any((q) => q.reasoning.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '出题思路仅在生成过程中展示，确认后不会随任务保存。',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        // 有单题失败：醒目提示「少题」，避免家长以为题已出齐。
        if (failures.isNotEmpty)
          _FailureBanner(
            text: '有 ${failures.length} 道题生成失败：${failures.join('；')}',
          ),
        // 生成中：当前题的内联推理区（题卡到达后折叠，见 _PreviewCard 的 info icon）。
        if (streaming && liveIndex >= 0)
          StreamReasoningPanel(
            index: liveIndex + 1,
            label: liveLabel,
            reasoning: liveReasoning,
            streaming: streaming,
          ),
        // key 用序号（列表只追加）→ PopIn 的 State 不重建，已在屏上的题卡
        // 不会因下一张到达而重放弹簧入场。
        ...questions.asMap().entries.map(
              (e) => PopIn(
                key: ValueKey<int>(e.key),
                child: _PreviewCard(index: e.key + 1, q: e.value),
              ),
            ),
      ],
    );
  }
}

/// 弹出「AI 出题思路」面板（ADR-0017）：纯前端交互，展示该题 reasoning，不编辑、不落库。
void _showReasoningSheet(BuildContext context, String reasoning) {
  final text = AppTheme.textOf(context);
  showCupertinoModalPopup(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('AI 出题思路'),
      message: SizedBox(
        height: 240,
        child: SingleChildScrollView(
          child: Text(
            reasoning,
            style: text.bodyMedium,
          ),
        ),
      ),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 少题警示条：出题过程中有单题失败时展示，避免家长误以为题已出齐。
///
/// 新粗野化：红色改走 `AppBrutal.red` 实心（深块，只能配白字 5.56:1），
/// 2px 墨黑描边 + 硬阴影——警示必须是全屏最强的视觉层级。
class _FailureBanner extends StatelessWidget {
  final String text;
  const _FailureBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final textStyle = AppTheme.textOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppBrutal.red,
        borderRadius: BorderRadius.circular(AppRadius.bubble),
        border: Border.all(
            color: AppBrutal.ink, width: AppElevation.borderWidth),
        boxShadow: AppElevation.hard(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 18, color: AppBrutal.onDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: textStyle.bodySmall?.copyWith(
                color: AppBrutal.onDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
    return AppFocusableAction(
      onTap: onTap,
      hoverHighlight: true,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      semanticLabel: label,
      child: AnimatedContainer(
        // 隐式动画**不会**自动尊重 reduce-motion，必须显式归零（ADR-0044）。
        duration: reducedMotionOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          // 选中态允许全填充（ADR-0044 仅 CTA 与选中态可全填）；
          // cyan 是亮块 → 只能配墨黑字（7.94:1）。
          color: selected ? AppBrutal.cyan : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: AppBrutal.ink,
            width: AppElevation.borderWidth,
          ),
          boxShadow: selected ? AppElevation.hard() : AppElevation.none,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(LucideIcons.check,
                    size: 16, color: AppBrutal.ink),
              ),
            Text(label,
                style: text.labelMedium?.copyWith(
                  color: AppBrutal.ink,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.bubble),
        border: Border.all(
            color: AppBrutal.ink, width: AppElevation.borderWidth),
        boxShadow: AppElevation.hard(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 题号用 violet（深块 → 白字 5.55:1），与学科 chip 的色相错开。
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppBrutal.violet,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                      color: AppBrutal.ink,
                      width: AppElevation.borderWidthSm),
                ),
                child: Text('第 $index 题',
                    style: text.labelSmall?.copyWith(
                        color: AppBrutal.onDark,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: AppSpacing.sm),
              // 学科走三重编码 chip（色 + 几何标记 + 文字），不再只靠纯文本。
              AppTags.subject(SubjectAccent.fromName(q.subject)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${q.grade}年级 · ${qtypeLabel(q.qtype)} · ${difficultyLabel(q.difficulty)}',
                  textAlign: TextAlign.end,
                  style: text.labelSmall?.copyWith(color: app.onSurfaceVariant),
                ),
              ),
              // 出题推理：卡片右上角 info icon，点击展开「AI 出题思路」（ADR-0017）。
              if (q.reasoning.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                AppIconAction(
                  icon: LucideIcons.info,
                  semanticLabel: '查看 AI 出题思路',
                  color: app.onSurfaceVariant,
                  onPressed: () => _showReasoningSheet(context, q.reasoning),
                ),
              ],
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
          // 出题思路：题卡落定后持久可见（不再只藏在右上角 info icon / 生成期一闪而过），
          // 让「生成中」闪现的推理在卡片上也能看清（ADR-0017 落地）。
          if (q.reasoning.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
                         Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppBrutal.paper,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                      color: AppBrutal.ink,
                      width: AppElevation.borderWidthSm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('出题思路',
                        style: text.labelSmall?.copyWith(
                            color: AppBrutal.violet,
                            fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(q.reasoning,
                      style: text.bodySmall?.copyWith(
                          color: app.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
