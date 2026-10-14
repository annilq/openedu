import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// LucideIcons 由 shadcn_ui 再导出。
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_scroll_page.dart';
import '../../../../../shared/widgets/app_section_title.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../../shared/widgets/class_picker.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import '../../../../model_management/presentation/providers/models_notifier.dart';
import '../../../../model_management/presentation/widgets/model_selector.dart';
import '../../../../../shared/presentation/resource.dart';
import '../../providers/home_notifier.dart';
import '../../providers/task_form_prefill.dart';
import 'student_picker.dart';
import 'dispatch_targets_row.dart';
import 'package:kids_learn/shared/features/materials/domain/repositories/material_repository.dart'
    show KnowledgePointOption;
import 'teacher_task_preview_section.dart';
import 'teacher_task_spec_row.dart';
import 'directory_notice_bar.dart';
import 'task_spec_row_data.dart';
import 'task_form_defaults.dart';
import 'teacher_task_form_actions.dart';
import '../../../providers/home_provider.dart';

/// 布置练习任务右栏：多学科行表单 + 一键均分 + 生成（ADR-0004）。
///
/// ADR-0056 审阅闸门：生成结束**停在生成页**等教师确认，此时题卡只在内存里、尚未落库；
/// 只有点「确认」才会 POST /tasks/from-generated。
///
/// ADR-0057：本页只渲染 state，**不承担任何收尾动作**。确认成功后的提示、重置、
/// 刷新与进草稿页全部由 `HomeScreen` 负责——本页只在「发布任务」这一个动作态挂载（从「任务」页进入），
/// 教师一切走就被卸载，挂在这里的收尾逻辑会连人一起消失（成功不提示、失败静默）。
///
/// 三个区块各自成文件（规格行 / 预览）：本文件只留**表单状态与出口**
/// （行数据、总题数、模型、生成·确认·放弃）。区块挪走后本文件才装得下 ADR-0058
/// 的 400 行——挪之前是 810 行，其中 250 行是三个区块的排版。行的数据与视图分别
/// 在 `task_spec_row_data.dart` / `teacher_task_spec_row.dart`。
class TeacherTaskFormView extends ConsumerStatefulWidget {
  const TeacherTaskFormView({super.key});

  @override
  ConsumerState<TeacherTaskFormView> createState() => _TeacherTaskFormViewState();
}

class _TeacherTaskFormViewState extends ConsumerState<TeacherTaskFormView> {
  /// 初始行留空——学科/知识点/题型/题数的初始值没有数据通路，由教师选填
  /// （CTA 预填除外，见 initState）；曾用硬编码常量（数学/两位数加减法/calc/4）
  /// 冒充默认值，只选班级就点生成会得到一份来历不明的二年级数学卷。
  final List<TaskSpecRow> _rows = [TaskSpecRow()];
  /// 派发目标：班级多选 + 学生多选（替代原单学生选择器，ticket 18）。
  List<ClassModel> _selectedClasses = [];
  List<UserModel> _selectedStudents = [];
  /// 总题数只服务「一键均分」，留空；均分前必须显式填写（曾硬编码 4）。
  final _totalCtrl = TextEditingController();
  /// 标题默认值按挂载日期生成，不是冻结的「今日练习」。
  final _titleCtrl =
      TextEditingController(text: defaultTaskTitle(DateTime.now()));

  // 多模型（票据 08）：出题时自选模型；null = 后端自动（默认/全局）。
  String? _modelId;

  // 反馈边（ADR-0060 D1）：从掌握度看板「就这个知识点出题」带过来的代表错题 id，
  // 用于同类题仿写；null = 普通出题。
  List<String>? _weakExampleIds;

  /// 出题年级锚点（ADR-0086 修正）：学生不再持有独立年级，年级完全由所选班级承载。
  /// 未选派发班级时为 null——兜底 2 会让没选班的教师静默拿到二年级的卷子。
  int? get _primaryGrade {
    if (_selectedClasses.isNotEmpty) return _selectedClasses.first.grade;
    return null;
  }

  /// 出题参考学生锚点（后端仅作 prompt 上下文）：首个已选学生，无则 null。
  String? get _primaryStudentId => _selectedStudents.firstOrNull?.id;

  @override
  void initState() {
    super.initState();
    // 反馈边预填：掌握度看板 CTA 写入 taskFormPrefillProvider 后请求跳转，
    // 本页挂载时读取、套用到首行（学科/知识点/年级）、消费后清空，避免残留到
    // 下次手动出题。
    final prefill = ref.read(taskFormPrefillProvider);
    if (prefill != null) {
      final row = _rows[0];
      // 学科经 onSubjectChanged 落入，题型随学科白名单派生（ADR-0055 §12），
      // 与教师手动选学科同一条路。
      final s = prefill.subject;
      if (s != null) row.onSubjectChanged(s);
      row.knowledgePoint.text = prefill.knowledgePoint;
      final g = prefill.grade;
      if (g != null) row.grade = g;
      _weakExampleIds =
          prefill.weakExampleIds.isNotEmpty ? prefill.weakExampleIds : null;
      // 消费后清空，避免残留到下次手动出题。Riverpod 禁止在 initState 构建期改
      // provider（_debugCanModifyProviders），延后到本帧构建结束后再清；mounted
      // 守卫防表单恰在此时卸载后操作已释放的 ref。
      Future.microtask(() {
        if (mounted) ref.read(taskFormPrefillProvider.notifier).state = null;
      });
    }
    // 预拉取可选模型列表，供模型选择器展示（仅教师可见自定义模型）。
    Future.microtask(() => ref.read(modelsNotifierProvider.notifier).load());
    // 隐藏「默认」选项后必须显式选模型：模型列表加载完成后，若尚未选择则回落到
    // 教师设为默认的模型（否则取列表首项），保证出题请求带有效 model 而非 null。
    ref.listenManual(modelsNotifierProvider, (prev, next) {
      if (next.dataOrNull == null || _modelId != null) return;
      final all = next.dataOrNull!.resp.custom;
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

  /// 加一行学科规格（多学科组卷的入口）：新行全空——「语文/字词积累」曾是硬编码，
  /// 点一下就凭空多出两样没选过的东西。
  void _addRow() => setState(() => _rows.add(TaskSpecRow()));

  /// 表单内选择派发班级：返回完整选中集合（含已选），直接覆盖。
  Future<void> _pickClasses() async {
    final picked = await pickClasses(
      context,
      classes: ref.read(classesRepositoryProvider).getClasses(),
      initialSelectedIds: _selectedClasses.map((c) => c.id).toList(),
    );
    if (picked.isNotEmpty) setState(() => _selectedClasses = picked);
  }

  /// 表单内选择派发学生：返回完整选中集合（含已选），直接覆盖。
  Future<void> _pickStudents() async {
    final picked = await pickStudents(
      context,
      ref,
      initialSelectedIds: _selectedStudents.map((s) => s.id).toList(),
    );
    if (picked.isNotEmpty) setState(() => _selectedStudents = picked);
  }

  void _removeRow(int i) => setState(() {
    if (_rows.length > 1) {
      _rows[i].dispose();
      _rows.removeAt(i);
    }
  });

  /// 一键均分（ADR-0004 D5）：总题数按当前行数等分，余数给前几行。
  /// 总题数留空即未填写——曾经回落硬编码 4，点一下均分就把每行刷成来历不明的数字。
  void _evenSplit() {
    final total = int.tryParse(_totalCtrl.text);
    if (total == null || total < 1) {
      AppToast.show(context, '请先填写总题数');
      return;
    }
    final n = _rows.length;
    if (n == 0) return;
    if (total < n) {
      AppToast.show(context, '总题数不能少于行数（每行至少 1 题）');
      return;
    }
    final base = total ~/ n;
    final extra = total % n;
    setState(() {
      for (var i = 0; i < n; i++) {
        _rows[i].count.text = (base + (i < extra ? 1 : 0)).toString();
      }
    });
  }

  /// 各行 → 出题规格；年级未定的行转不出规格（toSpec 返 null），由 _generate
  /// 的行级校验先行拦截，null 规格不会流进请求。
  List<TaskSpecModel> _currentSpecs() => _rows
      .map((r) => r.toSpec(_primaryGrade))
      .whereType<TaskSpecModel>()
      .toList();

  void _generate() {
    if (_selectedClasses.isEmpty && _selectedStudents.isEmpty) {
      AppToast.show(context, '请先选择要布置的班级或学生');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      AppToast.show(context, '请填写试卷标题');
      return;
    }
    for (final r in _rows) {
      final err = specRowError(r, inheritedGrade: _primaryGrade);
      if (err != null) {
        AppToast.show(context, err);
        return;
      }
    }
    final specs = _currentSpecs();
    // 生成任务：先流式逐题渲染题卡（消除真实模型超时），流结束后再落库为草稿。
    ref
        .read(taskGenNotifierProvider.notifier)
        .generate(
          studentId: _primaryStudentId,
          classIds: _selectedClasses.map((c) => c.id).toList(),
          studentIds: _selectedStudents.map((s) => s.id).toList(),
          title: _titleCtrl.text,
          specs: specs,
          model: _modelId,
          weakExampleIds: _weakExampleIds,
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
              DispatchTargetsRow(
                classes: _selectedClasses,
                students: _selectedStudents,
                onPickClasses: _pickClasses,
                onPickStudents: _pickStudents,
                onRemoveClass: (c) =>
                    setState(() => _selectedClasses.remove(c)),
                onRemoveStudent: (s) =>
                    setState(() => _selectedStudents.remove(s)),
              ),
              const SizedBox(height: AppSpacing.md),
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
                      hintText: '如 10',
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
              if (_directoryNotice case final notice?) ...[
                DirectoryNoticeBar(text: notice),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.xl),
              ModelSelector(
                selected: _modelId,
                onChanged: (v) => setState(() => _modelId = v),
                showDefaultOption: false,
              ),
              const SizedBox(height: AppSpacing.xl),
              // 流式生成 / 落库期间：隐藏按钮；首张题卡到达前显示加载动画，
              // 之后仅展示题卡（题卡逐张浮现），不重复显示 spinner。
              buildTaskFormActions(
                genState: genState,
                onConfirm: _confirm,
                onRegenerate: _generate,
                onDiscard: _discard,
                onGenerate: _generate,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (genState is TaskGenPreview || genState is TaskGenReady)
                TaskPreviewSection(state: genState),
            ],
          ),
        ),
      ],
    );
  }

  /// 学科规格行。年级的兜底（未指定 → 继承派发班级年级，未选班则留空由教师在
  /// 行内选）在此解析好再传给编辑器：编辑器是纯展示的，不该为了取兜底值去认识
  /// `classesRepositoryProvider`。知识点目录按 (学科, 年级, 学期) 联动加载（ADR-0055 §4 /
  /// ADR-0061），加载失败按空目录兜底——选项里仍保留当前文本，教师不至于被一次
  /// 网络抖动卡死在表单上。
  List<Widget> _buildSpecRows() {
    return [
      for (var i = 0; i < _rows.length; i++)
        TaskSpecRowEditor(
          subject: _rows[i].subject,
          onSubjectChanged: (v) => setState(() => _rows[i].onSubjectChanged(v)),
          knowledgePoint: _rows[i].knowledgePoint,
          qtype: _rows[i].qtype,
          onQtypeChanged: (v) => setState(() => _rows[i].qtype = v),
          count: _rows[i].count,
          grade: _rows[i].grade ?? _primaryGrade,
          onGradeChanged: (v) => setState(() => _rows[i].grade = v),
          semester: _rows[i].semester,
          onSemesterChanged: (v) => setState(() => _rows[i].semester = v),
          removable: _rows.length > 1,
          index: i,
          onRemove: () => _removeRow(i),
          knowledgePointOptions: _knowledgePointOptions(
            _rows[i].subject,
            _rows[i].grade ?? _primaryGrade,
            _rows[i].semester,
          ),
        ),
    ];
  }

  /// 某行 (学科, 年级, 学期) 的知识点目录；未加载 / 失败返回 null（编辑器按空处理）。
  List<KnowledgePointOption>? _knowledgePointOptions(
    String? subject,
    int? grade,
    String semester,
  ) {
    // provider family key 不接受 null，没定范围就不发请求；编辑器按空目录显示占位。
    if (subject == null || grade == null) return null;
    final async = ref.watch(
      knowledgePointsProvider((subject, grade, semester)),
    );
    return async.valueOrNull?.items;
  }

  /// 当前范围内「只有骨架兜底、没有真实知识点」时的说明（ADR-0061 §L）。
  ///
  /// 骨架不分学期，所以这种范围下切学期拿到的下拉逐字相同。不解释的话教师会以为
  /// 联动坏了——实际只是该学期还没上传资料。只在第一行提示，避免多行时刷屏。
  String? get _directoryNotice {
    if (_rows.isEmpty) return null;
    final first = _rows.first;
    final subject = first.subject;
    final grade = first.grade ?? _primaryGrade;
    // 范围未定（学科/年级至少缺一）时没有目录可解释，不刷说明条。
    if (subject == null || grade == null) return null;
    final async = ref.watch(
      knowledgePointsProvider((subject, grade, first.semester)),
    );
    final notice = async.valueOrNull?.notice ?? '';
    return notice.isEmpty ? null : notice;
  }

  /// 审阅闸门 / 动作区已抽到 `teacher_task_form_actions.dart`（ADR-0058 P4）：
  /// 生成结束停在生成页等教师拍板，确认/重新生成/放弃三出口语义见该文件。

  /// 确认：把内存里的题卡落库为 draft 任务，成功后由 [ref.listen] 跳草稿页。
  void _confirm() {
    ref.read(taskGenNotifierProvider.notifier).confirm();
  }

  /// 放弃：题卡只在内存里，丢弃即可，不需要调任何删除接口（ADR-0056）。
  void _discard() {
    ref.read(taskGenNotifierProvider.notifier).discard();
  }

}

