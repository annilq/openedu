import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../app_empty_state.dart';
import 'reflection_scene.dart';
import 'reflection_scene_data.dart';

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
///
/// **选项组优先**（ADR-0061 §O）：spec 带 `optionGroup` 时不渲染单个场景，而是
/// 展开成「每个选项一个独立可交互场景」——同一份模板派生多份实例，学生逐个亲手
/// 旋转/平移对称轴去验证，而不是看程序报答案。
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
    final group = spec['optionGroup'];
    if (group is Map && group['items'] is List && (group['items'] as List).isNotEmpty) {
      return SceneOptionGroup(
        spec: spec,
        items: (group['items'] as List)
            .whereType<Map>()
            .map((e) => SceneOptionItem.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.points != null)
            .toList(growable: false),
      );
    }
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

/// 一个选项对应的场景实例（ADR-0061 §O）。
class SceneOptionItem {
  /// 选项标号（「A」「B」…），仅用于界面定位，不参与判定。
  final String label;

  /// 图形中文名（副标题，如「房子」）。
  final String? caption;

  /// 该选项的顶点（归一化）。null = 该项没有可渲染几何，应被过滤掉。
  final List<Offset>? points;

  /// 该图形的默认对称轴角度（度）。
  final double? defaultAxisAngle;

  const SceneOptionItem({
    required this.label,
    this.caption,
    this.points,
    this.defaultAxisAngle,
  });

  factory SceneOptionItem.fromJson(Map<String, dynamic> json) => SceneOptionItem(
        label: (json['label'] as String?) ?? '',
        caption: json['caption'] as String?,
        points: ReflectionSceneData.parsePoints(json['points']),
        defaultAxisAngle: (json['defaultAxisAngle'] as num?)?.toDouble(),
      );
}

/// 选项组：同一模板派生 N 个独立可交互场景，**Wrap** 排布（ADR-0061 §O）。
///
/// 为什么 Wrap 而不是固定两列网格：窄栏（紧凑档 <700）下固定两列会把每个场景
/// 压到看不清顶点；Wrap 让每个场景拿到「至少能看清一条轴」的宽度，窄了就自动
/// 换行，宽了就并排——对比着看正是这道题要的。
///
/// 每个场景是独立的 [ReflectionSceneWidget]（各自 State），所以拖 A 的轴不影响 B。
class SceneOptionGroup extends StatelessWidget {
  /// 原始 spec（提供轴默认值、controls、narrative 等共享项）。
  final Map<String, dynamic> spec;
  final List<SceneOptionItem> items;

  /// 每个场景的最小/最大宽度——低于 min 顶点与判定文字会糊在一起，高于 max 则
  /// 画布过大（[ReflectionSceneWidget] 的画布是**边长= 宽度**的正方形，宽度直接
  /// 决定高度；两列并排时 1200 宽的屏会让每个场景高达 ~590px，一屏放不下 4 个）。
  static const double _minItemWidth = 240;
  static const double _maxItemWidth = 360;

  const SceneOptionGroup({
    super.key,
    required this.spec,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.help_outline,
        title: '暂无可演示的选项',
        message: '这道题没有可图形化的选项，请先用文字讲解。',
      );
    }
    final base = ReflectionSceneData.fromSpec(spec);
    final text = AppTheme.textOf(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final item in items)
          SizedBox(
            // 窄屏（< 2×min+spacing）时 Wrap 会自己给满宽，无需额外处理
            width: _itemWidth(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 选项标号 + 图形名：让学生知道现在试的是哪个选项
                Row(
                  children: [
                    Text(
                      item.label,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.caption != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        item.caption!,
                        style: text.bodySmall?.copyWith(
                          color: AppTheme.colorsOf(context).onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                // 该选项的独立场景：顶点来自 items，轴初始值用该图形自己的默认轴
                // （spec 的 axisAngle 是**教师配的模板默认值**，不该覆盖每个图形
                // 各自的正确初始轴——否则箭头会停在竖轴、一开始就不重合）。
                ReflectionSceneWidget(
                  key: ValueKey('scene_opt_${item.label}'),
                  data: base.copyWith(
                    points: item.points,
                    figureLabel: item.caption,
                    axisAngle: item.defaultAxisAngle ?? base.axisAngle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 每项宽度：宽屏两列并排（对比着看），窄屏一列；始终夹在 [min, max] 之间。
  double _itemWidth(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width;
    final twoUp = _minItemWidth * 2 + AppSpacing.md;
    final share = available >= twoUp * 1.6
        ? (available - AppSpacing.md) / 2
        : available;
    return share.clamp(_minItemWidth, _maxItemWidth).toDouble();
  }
}
