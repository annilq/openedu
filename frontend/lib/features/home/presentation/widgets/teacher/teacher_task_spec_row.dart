import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../domain/repositories/material_repository.dart'
    show KnowledgePointOption;

/// 一行学科规格的编辑器（年级 + 学期 + 学科 + 知识点 + 题型 + 题数 + 删除）。
///
/// 单独成文件是因为它是表单里**唯一会重复 N 次**的结构（教师给一个任务配多个学科行），
/// 也是原 `teacher_task_form_view` 里最大的单个区块（81 行私有方法）。它不持有状态：
/// 值从外面进、改动以回调出去，「行」这份数据仍归表单所有（`_SpecRow` 带着两个
/// TextEditingController，生命周期必须和表单一致）。
///
/// 纯展示 + 回调，故**不** `ref.watch`：年级的兜底值由调用方解析好再传进来
/// （未手动指定时继承选中学生年级），否则这个 widget 就得认识 `selectedStudentProvider`。
///
/// **排列 = 填写顺序**（2026-10-05调整）：`年级 → 学期 → 学科` 三个范围项排在第一行、
/// `知识点 → 题型 → 题数` 排在第二行。前三者决定知识点的可选集（改任一项都会让
/// 知识点列表重新加载），先摆它们教师才「先定位范围、再挑知识点」；知识点紧跟其后，
/// 中间不插别的控件，避免视线在中间来回跳。
///
///仍用**两行**而非一行：6 个字段挤在紧凑档（<700）里每格仅 ~60px，选项文字被截断到
/// 无法辨认。两行下每格都有可用宽度，行高由同一批 label 决定、两行仍然齐平。
class TaskSpecRowEditor extends StatelessWidget {
  final String subject;
  final ValueChanged<String> onSubjectChanged;

  /// 知识点选择器（ADR-0055 §4）：控制器仍由表单持有（要跟着行一起 dispose），
  /// 但教师从**目录里选**而不是自由输入——受控目录是掌握度分组的前提。
  /// 选项由表单按 (学科, 年级, 学期) 联动加载后传入；当前文本不在目录里时由表单补进
  /// 选项（掌握度看板 CTA 预填的知识点不在骨架里，也不能凭空消失）。
  final TextEditingController knowledgePoint;

  final String qtype;
  final ValueChanged<String> onQtypeChanged;

  /// 题数输入框：同上。
  final TextEditingController count;

  /// 已解析的年级：`row.grade ?? 学生年级 ?? 2`。
  final int grade;
  final ValueChanged<int> onGradeChanged;

  /// 学期（ADR-0061 发布任务对接资料库）：'' = 不限/整学年；'上学期' / '下学期'。
  /// 选定后知识点目录按该学期联动，讲解时也能命中同学期的交互场景模板。
  final String semester;
  final ValueChanged<String> onSemesterChanged;

  /// 至少保留一行，故只有 [removable] 为真时画删除按钮。
  final bool removable;
  final int index;
  final VoidCallback onRemove;

  /// 目录选项（涌现 + 骨架），由表单按 (学科, 年级, 学期) 加载后传入；null = 目录尚未加载。
  ///
  /// 每项可选地带 [KnowledgePointOption.semester]（ADR-0061）：「不限学期」时后端
  /// 并集多个学期，同名知识点可能来自不同学期——带后缀让教师一眼分辨。
  final List<KnowledgePointOption>? knowledgePointOptions;

  const TaskSpecRowEditor({
    super.key,
    required this.subject,
    required this.onSubjectChanged,
    required this.knowledgePoint,
    required this.qtype,
    required this.onQtypeChanged,
    required this.count,
    required this.grade,
    required this.onGradeChanged,
    required this.semester,
    required this.onSemesterChanged,
    required this.removable,
    required this.index,
    required this.onRemove,
    this.knowledgePointOptions,
  });

  /// 知识点下拉的取值：[KnowledgePointOption.name] 列表 + 当前文本补位。
  ///
  /// 当前文本不在目录里时补进首项——掌握度看板 CTA 预填的知识点不在骨架里，
  /// 也不能凭空消失（否则教师一下拉就看到自己填的值"丢了"）。
  List<String> get knowledgePointValues {
    final values = <String>[...?knowledgePointOptions?.map((e) => e.name)];
    final current = knowledgePoint.text;
    if (current.isNotEmpty && !values.contains(current)) {
      values.insert(0, current);
    }
    return values;
  }

  /// 知识点下拉的显示标签：跨学期并集里给非当前学期的项加「（X学期）」后缀。
  ///
  /// 只在「不限学期」（跨学期并集）时加——限定了学期就都是同一个学期，加了是噪声。
  List<String> get knowledgePointLabels {
    final byName = {for (final e in knowledgePointOptions ?? const <KnowledgePointOption>[]) e.name: e};
    return [
      for (final name in knowledgePointValues)
        () {
          final sem = byName[name]?.semester ?? '';
          if (semester.isNotEmpty || sem.isEmpty || sem == semester) return name;
          return '$name（$sem）';
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：范围三元组（年级 / 学期 / 学科）——它们决定右侧知识点的可选集，
          // 故排在最前，符合「先定位范围、再挑知识点」的填写顺序。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: AppPickerField<int>(
                  label: '年级',
                  values: List.generate(9, (j) => j + 1),
                  labels: List.generate(9, (j) => '${j + 1}年级'),
                  value: grade,
                  onChanged: onGradeChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: AppPickerField<String>(
                  label: '学期',
                  values: kTaskSemesters,
                  labels: kTaskSemesterLabels,
                  value: semester,
                  onChanged: onSemesterChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: AppPickerField<String>(
                  label: '学科',
                  values: kTaskSubjects,
                  labels: kTaskSubjects,
                  value: subject,
                  onChanged: onSubjectChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // 第二行：目标与量（知识点 / 题型 / 题数 / 删除）。删除按钮用同款label
          // 行高的空 Text 占位镜像结构——而非硬编码 top padding——字体/间距
          // 令牌变更时仍自动对齐（与输入盒错位是教师报过的bug）。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppPickerField<String>(
                  label: '知识点',
                  values: knowledgePointValues,
                  labels: knowledgePointLabels,
                  value: knowledgePoint.text.isEmpty ? null : knowledgePoint.text,
                  placeholder: '请选择知识点',
                  onChanged: (v) => knowledgePoint.text = v,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: AppPickerField<String>(
                  label: '题型',
                  // 题型白名单按学科给（ADR-0055 §12）：英语没有计算题。
                  values: qtypesForSubject(subject),
                  labels: [
                    for (final q in qtypesForSubject(subject))
                      kQtypeLabels[q] ?? q
                  ],
                  value: qtype,
                  onChanged: onQtypeChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: AppTextField(
                  label: '题数',
                  controller: count,
                  keyboardType: TextInputType.number,
                ),
              ),
              if (removable) ...[
                const SizedBox(width: AppSpacing.sm),
                // 同行有 ShadSelect（标准档 40）：图标操作也必须走标准档命中区，
                // 否则 CupertinoButton 的 44×44 默认 minSize 会把这一行撑高 4px。
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('', style: AppTheme.textOf(context).titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    AppIconAction(
                      icon: LucideIcons.x,
                      iconSize: 20,
                      semanticLabel: '删除第 ${index + 1} 行',
                      onPressed: onRemove,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 学期选项（ADR-0061 发布任务对接资料库）：与后端 `KnowledgePoint.semester`
/// 同源取值。首项 '' = 不限/整学年——留空时知识点目录取整学年并集，讲解时
/// 先找同学期模板、找不到再回落整学年模板（见 `resolve_scene_spec_for_question`）。
const List<String> kTaskSemesters = <String>['', '上学期', '下学期'];

/// 学期选项的展示标签（值是 '' / '上学期' / '下学期'，标签把空值说人话）。
const List<String> kTaskSemesterLabels = <String>['不限学期', '上学期', '下学期'];

/// 学科选项（ADR-0055 §11）：收敛到 3 科，与后端 `SUBJECTS` 同源。
/// 存量其他学科的旧任务照常展示复习（冻结语义），只是不能新建。
const List<String> kTaskSubjects = <String>[
  '数学',
  '语文',
  '英语',
];

/// 题型白名单（ADR-0055 §12）：列表首项即该学科默认题型。
const Map<String, List<String>> kSubjectQtypes = <String, List<String>>{
  '数学': ['calc', 'choice', 'fill', 'open'],
  '语文': ['fill', 'choice', 'open'],
  '英语': ['choice', 'fill', 'open'],
};

/// 题型标识 → 中文标签。
const Map<String, String> kQtypeLabels = <String, String>{
  'calc': '计算',
  'choice': '选择',
  'fill': '填空',
  'open': '应用',
};

String defaultQtypeFor(String subject) =>
    kSubjectQtypes[subject]?.first ?? 'choice';

List<String> qtypesForSubject(String subject) =>
    kSubjectQtypes[subject] ?? const ['choice', 'fill', 'open'];
