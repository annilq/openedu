import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../domain/models/courseware_section.dart';

/// 环节「教师话术 / 提问卡」编辑器（T02 多段 + 重点标注）。
///
/// 从环节编辑弹窗里整块抽出来（ADR-0058 §2：一个文件只暴露一个公开物）。控制器与
/// 重点列表**仍由弹窗持有**——保存时要读每一段的文本，只有它知道何时保存；这里只
/// 负责按段渲染与把「加一段 / 切重点 / 移除」回传出去。
class SectionScriptSegmentsEditor extends StatelessWidget {
  const SectionScriptSegmentsEditor({
    super.key,
    required this.controllers,
    required this.emphasis,
    required this.onAdd,
    required this.onCycleEmphasis,
    required this.onRemove,
  });

  final List<TextEditingController> controllers;
  final List<CoursewareScriptEmphasis> emphasis;

  final VoidCallback onAdd;
  final ValueChanged<int> onCycleEmphasis;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('教师话术 / 提问卡（可分多段，每段可标重点）', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < controllers.length; i++) _segmentRow(i),
        AppTextAction(label: '添加一段', onPressed: onAdd),
      ],
    );
  }

  Widget _segmentRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppTextField(
              label: '第 ${index + 1} 段',
              controller: controllers[index],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppTextAction(
            label: _emphasisLabel(emphasis[index]),
            onPressed: () => onCycleEmphasis(index),
          ),
          AppTextAction(
            label: '移除',
            onPressed: () => onRemove(index),
          ),
        ],
      ),
    );
  }
}

String _emphasisLabel(CoursewareScriptEmphasis e) => switch (e) {
      CoursewareScriptEmphasis.none => '普通',
      CoursewareScriptEmphasis.bold => '加粗',
      CoursewareScriptEmphasis.highlight => '高亮',
    };
