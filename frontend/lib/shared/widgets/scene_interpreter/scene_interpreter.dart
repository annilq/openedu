import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../app_empty_state.dart';
import 'reflection_scene.dart';

// =====================================================================
// §场景解释器（ADR-0061 决策 7 / 8）
//
// 三处消费方（出题解析卡 / 错题本 / AI 伴学讲解卡）统一经此入口渲染交互讲解，
// 复用同一套渲染器。kind 词汇表前后端双登记：新增 kind 必须在此 + 后端 _KIND 同步。
// =====================================================================

/// 场景类型（前后端双登记，ADR-0061 决策 7）。
enum SceneKind { reflection, unknown }

extension SceneKindX on SceneKind {
  static SceneKind fromName(String? name) {
    switch (name) {
      case 'reflection':
        return SceneKind.reflection;
      default:
        return SceneKind.unknown;
    }
  }
}

/// 场景解释器：按 [kind] 将 SceneSpec（原始 JSON）分发到对应渲染器。
///
/// 未识别的 kind 走降级空态（ADR-0051：空态讲清「为什么空 + 下一步」）。
class SceneInterpreter extends StatelessWidget {
  final String kind;
  final Map<String, dynamic> spec;

  const SceneInterpreter({
    super.key,
    required this.kind,
    required this.spec,
  });

  @override
Widget build(BuildContext context) {
    switch (SceneKindX.fromName(kind)) {
      case SceneKind.reflection:
        return ReflectionSceneWidget(data: ReflectionSceneData.fromSpec(spec));
      case SceneKind.unknown:
        return const AppEmptyState(
          icon: Icons.help_outline,
          title: '暂不支持的交互讲解',
          message: '当前版本未实现该类型的交互演示，可先用文字讲解。',
        );
    }
  }
}
