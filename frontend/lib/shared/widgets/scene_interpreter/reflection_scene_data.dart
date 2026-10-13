import 'package:flutter/widgets.dart';

import '../../domain/figures.dart';
import '../../domain/scene_spec.dart';
import 'scene_shells.dart';

/// 轴对称场景数据（与 SceneSpec 解耦，可直接构造以便测试）。
///
/// **顶点驱动**（ADR-0061 §O / ADR-0083 / ADR-0091）：核心是 [points] 一组归一化顶点 +
/// [edges] 连接关系，本类不认识「房子/风筝」这类概念——图形是教学素材
/// （`shared/domain/figures.dart`），由后端随 spec 下发（`figure` / `options[]` 里
/// 每个图形带自己的顶点）。交互参数（对称轴初值、控件开关、引导文案）来自
/// kind 外壳（[SceneShell]），不进 SceneSpec。
class ReflectionSceneData {
  /// 归一化多边形顶点（x/y ∈ 0..1，y 向下）。这是场景的**唯一几何来源**。
  final List<Offset> points;

  /// 顶点连接关系（顶点索引对）。null/空 = 按顶点顺序闭合（简单多边形默认）。
  final List<List<int>>? edges;

  /// 图形中文名（仅界面标签，不参与渲染判定）。
  final String? figureLabel;

  final double axisAngle;
  final double axisX;
  final double axisY;
  final bool controlsPlay;
  final bool controlsScrub;
  final String? narrative;

  /// 是否在画布下方显示对称轴滑块（编辑器弹窗语境）。
  ///
  /// **不是 SceneSpec 字段**（ADR-0083 决策 5 已删 `editable`）：它是本 widget 的
  /// 展示开关，由调用方在构造时决定（如 [SceneInterpreter.showAxisControls]）。
  /// [fromSpec] 不再从 spec 读任何开关——新形 spec 只有几何（ADR-0091）。
  final bool showAxisControls;

  const ReflectionSceneData({
    required this.points,
    this.edges,
    this.figureLabel,
    this.axisAngle = 90,
    this.axisX = 0.5,
    this.axisY = 0.5,
    this.controlsPlay = true,
    this.controlsScrub = true,
    this.narrative,
    this.showAxisControls = true,
  });

  /// 覆盖轴参数 / 顶点（选项组里同一模板派生多个选项时复用其余字段）。
  ReflectionSceneData copyWith({
    List<Offset>? points,
    List<List<int>>? edges,
    String? figureLabel,
    double? axisAngle,
    double? axisX,
    double? axisY,
    bool? showAxisControls,
  }) =>
      ReflectionSceneData(
        points: points ?? this.points,
        edges: edges ?? this.edges,
        figureLabel: figureLabel ?? this.figureLabel,
        axisAngle: axisAngle ?? this.axisAngle,
        axisX: axisX ?? this.axisX,
        axisY: axisY ?? this.axisY,
        controlsPlay: controlsPlay,
        controlsScrub: controlsScrub,
        narrative: narrative,
        showAxisControls: showAxisControls ?? this.showAxisControls,
      );

  /// 由 SceneSpec 解析（ADR-0061 §9.1 / §O / ADR-0083 / ADR-0091）。
  ///
  /// 几何来源（决策 7「运行时零图库依赖」）：`spec.figure` 的**内联顶点 + 连接
  /// 关系**——ADR-0091 起几何的唯一载体就是 `Figure`，spec 顶层不再有
  /// `points`/`edges`（旧形一律被 [SceneSpec.tryParse] 拒绝，不做双读）。
  /// 没有 figure → [kFallbackFigure]（房子），**渲染期兜底**：只为直接调用方
  /// （创作 UI，如知识点编辑器）不出现空画布，**不参与落库**；解释器路径另有
  /// 空态门（figure 与 options 皆空 → AppEmptyState）。
  ///
  /// 交互参数（轴初值 / controls / narrative）从 kind 外壳取（[SceneShell.fromSource]）：
  /// 轴初值**不再**从 spec 读（ADR-0083 决策 5 把它们划给外壳；ADR-0091 后 spec
  /// 只存几何，存量轴初值由迁移脚本归一到外壳默认）。controls / narrative 同理。
  factory ReflectionSceneData.fromSpec(SceneSpec spec) {
    final shell = SceneShell.fromSource(spec.kind, spec.toJson());
    final figure = spec.figure;
    final inline =
        (figure != null && figure.vertices.length >= 3) ? figure : null;
    return ReflectionSceneData(
      points: inline != null
          ? <Offset>[for (final v in inline.vertices) Offset(v.x, v.y)]
          : kFallbackFigure.vertices
              .map((v) => Offset(v.x, v.y))
              .toList(growable: false),
      edges: inline != null
          ? ((inline.edges != null && inline.edges!.isNotEmpty)
              ? inline.edges
              : closedEdges(inline.vertices.length))
          : kFallbackFigure.edges,
      axisAngle: shell.axisAngle,
      axisX: shell.axisX,
      axisY: shell.axisY,
      controlsPlay: shell.controlsPlay,
      controlsScrub: shell.controlsScrub,
      narrative: shell.narrative,
      showAxisControls: true,
    );
  }
}

// 本文件是「数据与几何」层；渲染/交互/绘制在 `reflection_scene.dart`。
// 拆分的理由：ADR-0058 的 400 行棘轮——把数据模型与渲染器放一个文件会顶破基线。
//
// ADR-0091 起「 spec 的结构」由 `shared/domain/scene_spec.dart` 的 [SceneSpec] 类型
// 承担（保存即 `SceneSpec(…).toJson()`）：此前的顶层函数 `buildReflectionSceneSpec`
// 与裸 dict 适配层 `adaptSceneSpec` 随之删除——「一处结构」由类型本身保证，
// 再留一个产旧形 Map 的函数就是第二处形状。
