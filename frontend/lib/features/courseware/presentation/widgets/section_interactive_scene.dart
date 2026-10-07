import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';

/// 交互演示（ADR-0067 §6 切片 6，内容块统一化）。
///
/// 入参 [spec] **直接就是一份 ADR-0061 SceneSpec 的 Map**，本组件不做任何字段翻译：
/// 取出 `kind` 后原样交给 [SceneInterpreter]。与 [CoursewareSectionModel.kind] 解耦——
/// 演示页统一把顶层 `scene`（或旧数据回退的 payload）传进来，任何环节都能展示场景。
///
/// ⚠️ 这是切片 6「零渲染器改动」的执行点——本文件里**不出现任何 SceneSpec 字段**
/// （`points` / `axisAngle` / `optionGroup`…）。一旦这里开始按 section 的语义去
/// 重组 spec，说明 section 与 SceneSpec 的边界被腐蚀了（§6.1 熔断条件），
/// 应当停下改设计，而不是在这里加映射。
class SectionInteractiveScene extends StatelessWidget {
  const SectionInteractiveScene({
    super.key,
    required this.spec,
  });

  /// ADR-0061 SceneSpec 的 Map（顶层 `scene` 或旧数据回退的 payload）。
  final Map<String, dynamic> spec;

  /// 画布边长上限。
  ///
  /// [ReflectionSceneWidget] 的画布是「边长 = 可用宽度」的正方形——演示页是通栏的，
  /// 1920 宽的投影会画出一个 1920 高的画布，把底部行动条整个顶出屏幕。
  /// 这里收口到 [AppLayout.contentCard]（520），与
  /// `ReflectionSceneDialog.maxCanvasSide`（420）同口径，演示页略放宽一档。
  static const double maxCanvasSide = AppLayout.contentCard;

  @override
  Widget build(BuildContext context) {
    if (spec.isEmpty) {
      return const AppEmptyState(
        icon: LucideIcons.shapes,
        title: '这一环节还没有配置交互演示',
        message: '这一环节是交互演示，但还没有填入演示内容。回到课件编辑页打开'
            '场景编辑器，调好图形与对称轴后这里就会显示。',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 只按**可用宽度**取档（ADR-0045）：窄屏撑满，宽屏钉在上限并居中，
        // 绝不因为屏幕变宽就把画布一起放大。
        final side = constraints.hasBoundedWidth &&
                constraints.maxWidth < maxCanvasSide
            ? constraints.maxWidth
            : maxCanvasSide;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: side,
            child: SceneInterpreter(
              kind: spec['kind'] as String? ?? '',
              spec: spec,
            ),
          ),
        );
      },
    );
  }
}
