import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_inputs.dart';

/// 一行学科规格的编辑器（学科 + 知识点 + 题型 + 题数 + 年级 + 删除）。
///
/// 单独成文件是因为它是表单里**唯一会重复 N 次**的结构（家长给一个任务配多个学科行），
/// 也是原 `parent_task_form_view` 里最大的单个区块（81 行私有方法）。它不持有状态：
/// 值从外面进、改动以回调出去，「行」这份数据仍归表单所有（`_SpecRow` 带着两个
/// TextEditingController，生命周期必须和表单一致）。
///
/// 纯展示 + 回调，故**不** `ref.watch`：年级的兜底值由调用方解析好再传进来
/// （未手动指定时继承选中娃娃年级），否则这个 widget 就得认识 `selectedChildProvider`。
class TaskSpecRowEditor extends StatelessWidget {
  final String subject;
  final ValueChanged<String> onSubjectChanged;

  /// 知识点输入框：控制器由表单持有（要跟着行一起 dispose）。
  final TextEditingController knowledgePoint;

  final String qtype;
  final ValueChanged<String> onQtypeChanged;

  /// 题数输入框：同上。
  final TextEditingController count;

  /// 已解析的年级：`row.grade ?? 娃娃年级 ?? 2`。
  final int grade;
  final ValueChanged<int> onGradeChanged;

  /// 至少保留一行，故只有 [removable] 为真时画删除按钮。
  final bool removable;
  final int index;
  final VoidCallback onRemove;

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
    required this.removable,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: AppTextField(label: '知识点', controller: knowledgePoint),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: AppPickerField<String>(
              label: '题型',
              values: const ['calc', 'fill', 'choice', 'open'],
              labels: const ['计算', '填空', '选择', '应用'],
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
          const SizedBox(width: AppSpacing.md),
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
          if (removable) ...[
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
                  semanticLabel: '删除第 ${index + 1} 行',
                  onPressed: onRemove,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 内置学科选项（覆盖小学至初中 K9 全学科）。
///
/// 任务建接口（`taskGenNotifierProvider`）对 subject 仅原样存储、不做白名单校验，
/// 故此处可放开到全学科；tutor 答疑学科白名单受后端 `SUBJECTS` 约束，不在此列。
const List<String> kTaskSubjects = <String>[
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
