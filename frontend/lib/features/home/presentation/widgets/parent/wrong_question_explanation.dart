import 'package:flutter/widgets.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';

/// 错题卡的「查看解析」区：文字解析 + **交互讲解**（ADR-0061 §Q）。
///
/// 为什么家长端也要有图形（§Q）：「正方形有几条对称轴」这类题，答案 C 只是一行
/// 字；家长看到孩子拖轴试出 4 条，才真能理解孩子为什么选 C—— 图形在这里是给
/// **家长**看的理解辅助，不是给孩子的提示（题干本身文字已完整，学生端另有其卡）。
///
/// 为什么独立成文件：这个区要同时管**展开状态**、文字解析、图形渲染三件事，内联
/// 进 `_ParentWrongCard` 会把那个文件顶过 ADR-0058 的 400 行棘轮。
class WrongQuestionExplanation extends StatefulWidget {
  /// 解析文字（可为空——有图形时图形本身就是讲解）。
  final String explanation;

  /// 交互讲解场景（ADR-0061）；null / 无 kind → 只显示文字解析。
  final Map<String, dynamic>? sceneSpec;

  const WrongQuestionExplanation({
    super.key,
    required this.explanation,
    this.sceneSpec,
  });

  @override
  State<WrongQuestionExplanation> createState() =>
      _WrongQuestionExplanationState();
}

class _WrongQuestionExplanationState extends State<WrongQuestionExplanation> {
  /// 展开状态是「这一张卡的事」，不进 provider：翻页后卡片重建，折叠回去是对的。
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final hasExplanation = widget.explanation.trim().isNotEmpty;
    final spec = widget.sceneSpec;
    // 判定与学生端（wrong_questions_screen）一致，避免两端行为分叉。
    final hasScene = spec != null && spec['kind'] is String;
    // 有场景时也允许展开：即使解析文字为空，图形本身就是讲解。
    if (!hasExplanation && !hasScene) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextAction(
          label: _expanded ? '收起解析' : '查看解析',
          onPressed: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded) ...[
          if (hasExplanation)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('解析：${widget.explanation}',
                  style: text.bodyMedium),
            ),
          // 图形在文字解析**之后**：先给结论性文字，再给可动手验证的图形。
          if (hasScene) ...[
            AppTags.info('交互讲解'),
            const SizedBox(height: AppSpacing.sm),
            SceneInterpreter(kind: spec['kind'] as String, spec: spec),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ],
    );
  }
}
