import 'package:flutter/widgets.dart';

import '../../../../shared/domain/scene_spec.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../domain/assistant_card.dart';
import 'assistant_card_header.dart';

/// 交互讲解卡（`interactive_scene`）：聊天内嵌的交互演示（ADR-0061 决策 7）。
///
/// 外层 DATA 帧 `data.type = interactive_scene`，载荷（SceneSpec）原样放进
/// [AssistantCard.rawPayload]；内层 `kind` 才是具体场景类型（如 `reflection` /
/// `bar_chart`），由 [SceneSpec.tryParse] 解析后交给 [SceneInterpreter] 按
/// `spec.kind` 分派渲染器（ADR-0091：解析只有这一处）。
///
/// 标题取自 SceneSpec 的 `title`（如「图形的运动（轴对称）」）；缺省回退「交互讲解」。
/// 渲染器自带播放 / 拖拽 / 分析交互，卡片本身只做容器 + 卡头，不重复造交互控件。
class AssistantInteractiveSceneCard extends StatelessWidget {
  final AssistantCard card;

  const AssistantInteractiveSceneCard({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    // 卡只在「有内容」时渲染（kind 存在，见 AssistantCard.hasContent），故解析
    // 正常非空；留 null 分支只为类型健全（畸形帧不画空壳）。
    final spec = SceneSpec.tryParse(card.rawPayload);
    final title =
        card.title.isNotEmpty ? card.title : '交互讲解';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AssistantCardHeader(
          title: title,
          kind: AssistantCardKind.interactiveScene,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (spec != null) SceneInterpreter(spec: spec),
      ],
    );
  }
}
