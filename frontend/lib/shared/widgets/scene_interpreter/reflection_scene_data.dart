import 'package:flutter/widgets.dart';

import '../../domain/figures.dart';

/// 轴对称场景数据（与 SceneSpec JSON 解耦，可直接构造以便测试）。
///
/// **顶点驱动**（ADR-0061 §O）：核心是 [points] 一组归一化顶点，本类不认识
/// 「房子/风筝」这类概念——图形是教学素材（`shared/domain/figures.dart`），
/// 由后端随spec 下发（选项组里每个选项带自己的 points），缺省才回退内置预设。
class ReflectionSceneData {
  /// 归一化多边形顶点（x/y ∈ 0..1，y 向下）。这是场景的**唯一几何来源**。
  final List<Offset> points;

  /// 图形中文名（仅界面标签，不参与渲染判定）。
  final String? figureLabel;

  final double axisAngle;
  final double axisX;
  final double axisY;
  final bool controlsPlay;
  final bool controlsScrub;
  final String? narrative;
  final bool editable;
  final bool lockedAxisymmetric;

  const ReflectionSceneData({
    required this.points,
    this.figureLabel,
    this.axisAngle = 90,
    this.axisX = 0.5,
    this.axisY = 0.5,
    this.controlsPlay = true,
    this.controlsScrub = true,
    this.narrative,
    this.editable = true,
    this.lockedAxisymmetric = true,
  });

  /// 由内置预设构造（教师调参面板用：面板就是「挑一个图形预设→ 调轴」）。
  factory ReflectionSceneData.fromPreset(
    FigureShape shape, {
    double axisAngle = 90,
    double axisX = 0.5,
    double axisY = 0.5,
    bool editable = true,
    String? narrative,
  }) =>
      ReflectionSceneData(
        points: shape.vertices
            .map((v) => Offset(v.x, v.y))
            .toList(growable: false),
        figureLabel: shape.label,
        axisAngle: axisAngle,
        axisX: axisX,
        axisY: axisY,
        narrative: narrative,
        editable: editable,
      );

  /// 覆盖轴参数（选项组里同一模板派生多个选项时复用其余字段）。
  ReflectionSceneData copyWith({
    List<Offset>? points,
    String? figureLabel,
    double? axisAngle,
    double? axisX,
    double? axisY,
  }) =>
      ReflectionSceneData(
        points: points ?? this.points,
        figureLabel: figureLabel ?? this.figureLabel,
        axisAngle: axisAngle ?? this.axisAngle,
        axisX: axisX ?? this.axisX,
        axisY: axisY ?? this.axisY,
        controlsPlay: controlsPlay,
        controlsScrub: controlsScrub,
        narrative: narrative,
        editable: editable,
        lockedAxisymmetric: lockedAxisymmetric,
      );

  /// 由 SceneSpec 解析（ADR-0061 §9.1 / §O）。
  ///
  /// 几何来源优先级：
  /// 1. `inputs[].key == 'points'`（新：后端下发的顶点，`[[x,y],...]`）；
  /// 2. `inputs[].key == 'figure'` 的预设 key（兼容旧 spec / 教师面板存的预设名）；
  /// 3. 都没有 → 房子（首个预设），保证**永不出现空场景**。
  ///
  /// `[defaultAxisAngle]` 只在「按预设回退」时生效：spec 显式给了 `axisAngle`
  /// 就用spec 的（教师/题目设定的初始轴优先于图形默认轴）。
  factory ReflectionSceneData.fromSpec(
    Map<String, dynamic> spec, {
    FigureShape? presetOverride,
  }) {
    final inputs = (spec['inputs'] as List?) ?? <dynamic>[];
    var axisAngle = 90.0;
    var axisX = 0.5;
    var axisY = 0.5;
    var axisAngleGiven = false;
    List<Offset>? points;
    String? figureKey;
    for (final raw in inputs) {
      final m = raw as Map<String, dynamic>;
      final key = m['key'] as String?;
      final val = m['value'];
      switch (key) {
        case 'axisAngle':
          if (val is num) {
            axisAngle = val.toDouble();
            axisAngleGiven = true;
          }
        case 'axisX':
          if (val is num) axisX = val.toDouble();
        case 'axisY':
          if (val is num) axisY = val.toDouble();
        case 'points':
          points = parsePoints(val);
        case 'figure':
          if (val is String) figureKey = val;
      }
    }
    // 几何回退链：spec 顶点 → 预设（显式指定 or inputs 里的 figure key）→ 房子
    //（figureByKey 未命中也回落首个预设，故 preset 非空；显式 override 优先。）
    final preset = presetOverride ?? figureByKey(figureKey);
    final pointsOrFallback = (points != null && points.length >= 3)
        ? points
        : preset.vertices.map((v) => Offset(v.x, v.y)).toList(growable: false);
    // 轴角度：spec 显式给 > 预设默认 > 90
    final resolvedAngle =
        axisAngleGiven ? axisAngle : preset.defaultAxisAngle;
    final controls = spec['controls'] as Map? ?? <String, dynamic>{};
    final outputs = spec['outputs'] as Map? ?? <String, dynamic>{};
    return ReflectionSceneData(
      points: pointsOrFallback,
      figureLabel: preset.label,
      axisAngle: resolvedAngle,
      axisX: axisX,
      axisY: axisY,
      controlsPlay: controls['play'] as bool? ?? true,
      controlsScrub: controls['scrub'] as bool? ?? true,
      narrative: spec['narrative'] as String?,
      editable: spec['editable'] as bool? ?? true,
      lockedAxisymmetric: outputs['isAxisymmetric'] as bool? ?? true,
    );
  }

  /// 解析顶点：接受 `[[x,y],...]`（后端下发形态）。
  /// 容忍 `[x, y]` 扁平二元组与 `{"x":..,"y":..}`，非法项跳过。
  static List<Offset>? parsePoints(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final out = <Offset>[];
    for (final item in raw) {
      if (item is List && item.length >= 2) {
        final x = item[0];
        final y = item[1];
        if (x is num && y is num) out.add(Offset(x.toDouble(), y.toDouble()));
      } else if (item is Map && item['x'] is num && item['y'] is num) {
        out.add(
          Offset((item['x'] as num).toDouble(), (item['y'] as num).toDouble()),
        );
      }
    }
    return out.isEmpty ? null : out;
  }
}

// 本文件是「数据与几何」层；渲染/交互/绘制在 `reflection_scene.dart`。
// 拆分的理由：ADR-0058 的 400 行棘轮——把数据模型与渲染器放一个文件会顶破基线。
