import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// LucideIcons 由 shadcn_ui 再导出。
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_scroll_page.dart';
import '../../../../../shared/widgets/app_section_title.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../model_management/presentation/providers/models_notifier.dart';
import '../../../../model_management/presentation/widgets/model_selector.dart';
import '../../providers/home_notifier.dart';
import '../../providers/selected_child_provider.dart';
import 'parent_task_interest_section.dart';
import 'parent_task_preview_section.dart';
import 'parent_task_spec_row.dart';

/// 布置练习任务右栏：多学科行表单 + 一键均分 + 生成（ADR-0004）。
///
/// ADR-0056 审阅闸门：生成结束**停在生成页**等家长确认，此时题卡只在内存里、尚未落库；
/// 只有点「确认」才会 POST /tasks/from-generated。
///
/// ADR-0057：本页只渲染 state，**不承担任何收尾动作**。确认成功后的提示、重置、
/// 刷新与进草稿页全部由 `HomeScreen` 负责——本页只在「布置任务」这一个侧栏索引挂载，
/// 家长一切走就被卸载，挂在这里的收尾逻辑会连人一起消失（成功不提示、失败静默）。
///
/// 三个区块各自成文件（规格行 / 兴趣 / 预览）：本文件只留**表单状态与出口**
/// （行数据、总题数、模型、生成·确认·放弃）。区块挪走后本文件才装得下 ADR-0058
/// 的 400 行——挪之前是 810 行，其中 250 行是三个区块的排版。
class ParentTaskFormView extends ConsumerStatefulWidget {
  const ParentTaskFormView({super.key});

  @override
  ConsumerState<ParentTaskFormView> createState() => _ParentTaskFormViewState();
}

/// 一行学科规格（学科 + 知识点 + 题型 + 题量 + 年级）。
///
/// 持有两个 [TextEditingController]，所以**生命周期必须归表单**：行的编辑器
/// （[TaskSpecRowEditor]）是纯展示的，行本身跟着表单一起 dispose。
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
    return AppScrollPage(
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
              ..._buildSpecRows(),
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
                TaskPreviewSection(state: genState),
            ],
          ),
        ),
      ],
    );
  }

  /// 学科规格行。年级的兜底（未指定 → 继承娃娃年级 → 2）在此解析好再传给编辑器：
  /// 编辑器是纯展示的，不该为了取兜底值去认识 `selectedChildProvider`。
  List<Widget> _buildSpecRows() {
    final selected = ref.watch(selectedChildProvider);
    return [
      for (var i = 0; i < _rows.length; i++)
        TaskSpecRowEditor(
          subject: _rows[i].subject,
          onSubjectChanged: (v) => setState(() => _rows[i].subject = v),
          knowledgePoint: _rows[i].knowledgePoint,
          qtype: _rows[i].qtype,
          onQtypeChanged: (v) => setState(() => _rows[i].qtype = v),
          count: _rows[i].count,
          grade: _rows[i].grade ?? selected?.grade ?? 2,
          onGradeChanged: (v) => setState(() => _rows[i].grade = v),
          removable: _rows.length > 1,
          index: i,
          onRemove: () => _removeRow(i),
        ),
    ];
  }

  Widget _buildInterestSection() {
    return TaskInterestSection(
      enabled: _useInterestMode,
      onEnabledChanged: (v) => setState(() {
        _useInterestMode = v;
        if (!v) _focusThemes.clear();
      }),
      selectedThemes: _focusThemes,
      onToggleTheme: (t) => setState(() {
        if (_focusThemes.contains(t)) {
          _focusThemes.remove(t);
        } else {
          _focusThemes.add(t);
        }
      }),
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
}
