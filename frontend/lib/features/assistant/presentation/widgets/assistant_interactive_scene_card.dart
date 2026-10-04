import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../domain/assistant_card.dart';
import 'assistant_card_header.dart';

/// 交互讲解卡（`interactive_scene`）：聊天内嵌的交互演示（ADR-0061 决策 7）。
///
/// 外层 DATA 帧 `data.type = interactive_scene`，载荷（SceneSpec）原样放进
/// [AssistantCard.rawPayload]；内层 `rawPayload['kind']` 才是具体场景类型
/// （如 `reflection` / `bar_chart`），交给 [SceneInterpreter] 按 kind 分派渲染器。
///
/// 标题取自 SceneSpec 的 `title`（如「图形的运动（轴对称）」）；缺省回退「交互讲解」。
/// 渲染器自带播放 / 拖拽 / 分析交互，卡片本身只做容器 + 卡头，不重复造交互控件。
class AssistantInteractiveSceneCard extends StatelessWidget {
  final AssistantCard card;

  const AssistantInteractiveSceneCard({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final spec = card.rawPayload;
    final sceneKind =
        spec['kind'] is String ? spec['kind'] as String : '';
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
        SceneInterpreter(kind: sceneKind, spec: spec),
      ],
    );
  }
}
