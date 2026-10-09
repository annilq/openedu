import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../domain/models/courseware.dart';

/// 课件信息编辑（courseware-round-3 T02）：标题 + 状态。
///
/// 复用已有 `PATCH /courseware/{id}`（[CoursewareRepository.updateCourseware]，
/// 无需新端点）。返回更新后的 `(title, status)`；取消回 null。
///
/// 状态只有两档：草稿（还在调）/ 可上讲台（可以直接上讲台）——不阻塞演示，只是列表标签。
typedef CoursewareInfoEdit = ({String title, String status});

Future<CoursewareInfoEdit?> showCoursewareInfoEditDialog(
  BuildContext context,
  CoursewareModel cw,
) =>
    showDialog<CoursewareInfoEdit>(
      context: context,
      builder: (_) => _CoursewareInfoEditDialog(cw: cw),
    );

class _CoursewareInfoEditDialog extends StatefulWidget {
  const _CoursewareInfoEditDialog({required this.cw});

  final CoursewareModel cw;

  @override
  State<_CoursewareInfoEditDialog> createState() =>
      _CoursewareInfoEditDialogState();
}

class _CoursewareInfoEditDialogState extends State<_CoursewareInfoEditDialog> {
  late final TextEditingController _titleCtl;
  late String _status;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.cw.title);
    _status = widget.cw.status == 'ready' ? 'ready' : 'draft';
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(
        context,
        (
          title: _titleCtl.text.trim(),
          status: _status,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('课件信息', style: text.titleLarge),
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: '课件标题', controller: _titleCtl),
              const SizedBox(height: AppSpacing.md),
              AppPickerField<String>(
                label: '状态',
                values: const ['draft', 'ready'],
                labels: const ['草稿（还在调）', '可上讲台（可直接讲）'],
                value: _status,
                placeholder: '请选择状态',
                onChanged: (v) => setState(() => _status = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppTextAction(
                    label: '取消',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppPrimaryButton(
                    label: '保存',
                    fullWidth: false,
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
