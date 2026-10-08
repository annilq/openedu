import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/domain/models/class_model.dart';
import '../../../../../shared/domain/models/user.dart';

/// 布置任务的「派发目标」多选行：展示已选班级 / 学生 chip（可移除）+ 添加入口。
///
/// 取代原先的单学生选择器（ticket 18）：一次布置可勾选整班与一批学生批量派发。
class DispatchTargetsRow extends StatelessWidget {
  final List<ClassModel> classes;
  final List<UserModel> students;
  final VoidCallback onPickClasses;
  final VoidCallback onPickStudents;
  final void Function(ClassModel) onRemoveClass;
  final void Function(UserModel) onRemoveStudent;

  const DispatchTargetsRow({
    super.key,
    required this.classes,
    required this.students,
    required this.onPickClasses,
    required this.onPickStudents,
    required this.onRemoveClass,
    required this.onRemoveStudent,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final scheme = AppTheme.colorsOf(context);
    final empty = classes.isEmpty && students.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('布置给',
            style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        if (empty)
          Text('未选择',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in classes)
                _Chip(
                  label: '${c.name} (${c.grade}年级)',
                  onRemove: () => onRemoveClass(c),
                ),
              for (final s in students)
                _Chip(label: s.displayName, onRemove: () => onRemoveStudent(s)),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          children: [
            AppTextAction(label: '添加班级', onPressed: onPickClasses),
            AppTextAction(label: '添加学生', onPressed: onPickStudents),
          ],
        ),
      ],
    );
  }
}

/// 已选目标的可移除 chip：描边胶囊 + 末尾 X。
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _Chip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final scheme = AppTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.bodySmall),
          const SizedBox(width: AppSpacing.xs),
          AppFocusableAction(
            onTap: onRemove,
            hoverHighlight: true,
            semanticLabel: '移除 $label',
            child: Icon(LucideIcons.x,
                size: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
