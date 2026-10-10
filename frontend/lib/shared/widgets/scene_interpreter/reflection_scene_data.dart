import 'package:flutter/widgets.dart';

import '../../domain/figures.dart';
import 'scene_shells.dart';

/// 轴对称场景数据（与 SceneSpec JSON 解耦，可直接构造以便测试）。
///
/// **顶点驱动**（ADR-0061 §O / ADR-0083）：核心是 [points] 一组归一化顶点 +
/// [edges] 连接关系，本类不认识「房子/风筝」这类概念——图形是教学素材
/// （`shared/domain/figures.dart`），由后端随 spec 下发（选项组里每个选项带自己的
/// points），缺省才回退内置预设。交互参数（对称轴初值、控件开关、引导文案）来自
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
  /// 展示开关——编辑器面板自己有 3 个轴滑块，弹窗预览再画一遍是重复。由调用方在
  /// 构造时决定，不从 spec 解析。
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

  /// 由 SceneSpec 解析（ADR-0061 §9.1 / §O / ADR-0083）。
  ///
  /// 几何来源优先级：
  /// 1. 顶层 `points`（ADR-0083 新形：后端 / 画板内联的顶点，`[[x,y],...]`）；
  /// 2. 旧形 `inputs[].key == 'points'`（back-compat，T03 迁移前的存量数据）；
  /// 3. `figure` 预设 key 的顶点（旧 spec / 教师面板存的预设名）；
  /// 4. 都没有 → 房子（首个预设），保证**永不出现空场景**。
  ///
  /// 交互参数（轴初值 / controls / narrative）从 kind 外壳取（[SceneShell.fromSource]）：
  /// 显式字段优先（编辑器传后端 `defaults`），缺省回落该 kind 默认外壳。旧形 spec
  /// 的轴参数在 `inputs` 里，这里也一并读入以兼容存量数据。
  factory ReflectionSceneData.fromSpec(
    Map<String, dynamic> spec, {
    FigureShape? presetOverride,
  }) {
    final kind = spec['kind'] as String?;
    final shell = SceneShell.fromSource(kind, spec);

    // —— 旧形 inputs（back-compat；T03 起正式迁移为顶层几何）——
    final inputs = (spec['inputs'] as List?) ?? const <dynamic>[];
    double? oldAngle;
    double? oldAxisX;
    double? oldAxisY;
    List<Offset>? oldPoints;
    String? oldFigure;
    for (final raw in inputs) {
      if (raw is! Map) continue;
      final key = raw['key'] as String?;
      final val = raw['value'];
      switch (key) {
        case 'axisAngle':
          if (val is num) oldAngle = val.toDouble();
        case 'axisX':
          if (val is num) oldAxisX = val.toDouble();
        case 'axisY':
          if (val is num) oldAxisY = val.toDouble();
        case 'points':
          oldPoints = parsePoints(val);
        case 'figure':
          if (val is String && val.isNotEmpty) oldFigure = val;
      }
    }

    final points = parsePoints(spec['points']) ?? oldPoints;
    final figureKey = (spec['figure'] as String?) ?? oldFigure;
    // 几何回退链：spec 顶点 → 预设（显式 override 或 figure key）→ 房子
    //（figureByKey 未命中也回落首个预设，故 preset 非空）。
    final preset = presetOverride ?? figureByKey(figureKey);
    final pointsOrFallback = (points != null && points.length >= 3)
        ? points
        : preset.vertices.map((v) => Offset(v.x, v.y)).toList(growable: false);
    return ReflectionSceneData(
      points: pointsOrFallback,
      edges: parseEdges(spec['edges']),
      figureLabel: preset.label,
      axisAngle: oldAngle ?? shell.axisAngle,
      axisX: oldAxisX ?? shell.axisX,
      axisY: oldAxisY ?? shell.axisY,
      controlsPlay: shell.controlsPlay,
      controlsScrub: shell.controlsScrub,
      narrative: shell.narrative,
      // 旧形 spec 的 editable 仅作 widget 展示开关沿用；新形 spec 无此字段。
      showAxisControls: (spec['editable'] as bool?) ?? true,
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

  /// 解析边：接受 `[[i,j],...]`（顶点索引对）。非法项跳过；空返回 null（= 默认闭合）。
  static List<List<int>>? parseEdges(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final out = <List<int>>[];
    for (final item in raw) {
      if (item is List && item.length >= 2) {
        final i = item[0];
        final j = item[1];
        if (i is int && j is int) out.add([i, j]);
      }
    }
    return out.isEmpty ? null : out;
  }
}

/// 顶点顺序闭合的边集（简单多边形的默认连接）。
List<List<int>> closedEdges(int n) =>
    [for (var i = 0; i < n; i++) [i, (i + 1) % n]];

/// 构造一个轴对称（reflection）场景的 SceneSpec（ADR-0061 §O / ADR-0083）。
///
/// 抽成顶层函数：知识点编辑器保存、场景库「关联知识点」seed 注入、未来批量生成
/// 都从这一处取结构。产出**纯几何** `{kind, points, edges}`——交互参数由 kind 外壳
/// 统一提供，不再进 spec（决策 5）。
Map<String, dynamic> buildReflectionSceneSpec({
  required String kind,
  required List<List<double>> points,
  List<List<int>>? edges,
}) =>
    <String, dynamic>{
      'kind': kind,
      'points': points,
      'edges': edges ?? closedEdges(points.length),
    };

// 本文件是「数据与几何」层；渲染/交互/绘制在 `reflection_scene.dart`。
// 拆分的理由：ADR-0058 的 400 行棘轮——把数据模型与渲染器放一个文件会顶破基线。
