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
  /// 展示开关，由调用方在构造时决定（如 [SceneInterpreter.showAxisControls]）。
  /// [fromSpec] 仅为兼容**存量快照**仍会读旧形 `editable`——新代码一律显式传参，
  /// 不再产出该键。
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
  /// 入口先过 [adaptSceneSpec] 适配层（ADR-0083 T03）：旧形 spec 的
  /// `inputs[key=='points']` 被上提为顶层几何，`controls` / `narrative` / `title` /
  /// `outputs` 被丢弃（它们已归 kind 外壳，不再从 spec 读）。之后本函数只认新形：
  /// 顶层 `points` / `edges`。
  ///
  /// 几何来源（决策 7「运行时零图库依赖」）：
  /// 1. 顶层 `points`（新形：后端 / 画板内联的顶点，`[[x,y],...]`）；
  /// 2. `inputs[key=='points']`（适配层已上提，此处与之等价）；
  /// 3. 都没有 → [kFallbackFigure]（房子），**极端兜底**，只为不出现空画布。
  ///    **不再按 `figure` key 回查图库**——图库只在创作 UI 打开时按需拉取
  ///    （`figureLibraryProvider`），运行时渲染零图库依赖。
  ///
  /// 交互参数（轴初值 / controls / narrative）从 kind 外壳取（[SceneShell.fromSource]）：
  /// 适配层把旧形 spec 里的轴初值上提到顶层（`axisAngle/axisX/axisY`），故存量数据的
  /// 轴初值仍被采信；controls / narrative 不再来自 spec，一律用外壳默认。
  factory ReflectionSceneData.fromSpec(Map<String, dynamic> spec) {
    final adapted = adaptSceneSpec(spec);
    final kind = adapted['kind'] as String?;
    final shell = SceneShell.fromSource(kind, adapted);

    final points = parsePoints(adapted['points']);
    final inline = (points != null && points.length >= 3) ? points : null;
    return ReflectionSceneData(
      points: inline ??
          kFallbackFigure.vertices
              .map((v) => Offset(v.x, v.y))
              .toList(growable: false),
      edges: parseEdges(adapted['edges']),
      axisAngle: shell.axisAngle,
      axisX: shell.axisX,
      axisY: shell.axisY,
      controlsPlay: shell.controlsPlay,
      controlsScrub: shell.controlsScrub,
      narrative: shell.narrative,
      // 旧形 spec 的 editable 仅作 widget 展示开关沿用；新形 spec 无此字段。
      showAxisControls: (adapted['editable'] as bool?) ?? true,
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

/// 旧 SceneSpec → 新 SceneSpec 的**适配层**（ADR-0083 T03）。
///
/// 为什么需要它：已落库的 `Question.scene_spec` / `kp.scenes` 是**快照**，不可回写
/// （本轮共同纪律「零回写 kp.scenes」），但它们的形状是 ADR-0083 之前的**老形**——
/// 几何塞在 `inputs[key=='points']`（或只留 `figure` 引用 key）、还带
/// `controls`/`narrative`/`title`/`outputs`/`editable`。渲染必须能同时吃下新老两种
/// 形状，故在读取入口统一适配（几何不丢、观感不变），而不是去改写历史快照。
///
/// 适配规则（**幂等**：新形输入原样通过）：
/// 1. **上提几何**：`inputs[key ∈ {points, figure, axisAngle, axisX, axisY}]` 的
///    `value` 提升为顶层同名字段（顶层已有则不覆盖——顶层是新形权威）。
/// 2. **丢弃已废字段**：`inputs`/`controls`/`narrative`/`title`/`outputs` 一律移除
///    ——它们已归 kind 外壳（ADR-0083 决策 5），渲染不再从 spec 读。留着它们会让
///    旧数据里的旧文案 / 旧控件开关盖掉外壳，把「外壳是唯一交互来源」这个不变量
///    悄悄破坏（且靠人肉同步）。
/// 3. **补默认边**：无 `edges` 但有 ≥3 个顶点时，按顶点顺序闭合（[closedEdges]）。
///    旧数据没有 `edges` 字段，这一步保证它们仍渲染成闭合多边形。
///
/// 保留 `editable`：它是**旧形**的展示开关（旧数据里 `editable=false` 表示不挂轴
/// 滑块），存量观感须一字不变，故沿用；新形 spec 不含此键（决策 5 已从新 spec 删除）。
/// `figure` 键仍会被上提：它是**存量数据的迁移线索**（旧 spec 可能只留了图形 key、
/// 没有内联顶点）。运行时**不再**按它回查图库（决策 7：运行时零图库依赖）——这类
/// 快照由一次性迁移脚本补齐内联几何；实在没有几何可画时统一回退 [kFallbackFigure]。
Map<String, dynamic> adaptSceneSpec(Map<String, dynamic> raw) {
  final out = <String, dynamic>{...raw};
  // 1. 旧形 inputs → 顶层（仅在新形没有对应顶层键时上提）。
  final inputs = raw['inputs'];
  if (inputs is List) {
    for (final item in inputs) {
      if (item is! Map) continue;
      final key = item['key'];
      if (key is! String) continue;
      final value = item['value'];
      switch (key) {
        case 'points':
          out.putIfAbsent('points', () => value);
        case 'figure':
          // 空串是旧种子的占位（「还没选图形」），不是有效的图形引用。
          if (value is String && value.isNotEmpty) {
            out.putIfAbsent('figure', () => value);
          }
        case 'axisAngle':
        case 'axisX':
        case 'axisY':
          if (value is num) out.putIfAbsent(key, () => value);
      }
    }
  }
  // 2. 移除已废字段（决策 5：交互 / 文案归 kind 外壳，spec 不再承载）。
  for (final banned in const [
    'inputs',
    'controls',
    'narrative',
    'title',
    'outputs',
  ]) {
    out.remove(banned);
  }
  // 3. 缺 edges 时按顶点顺序闭合（旧数据无 edges）。
  final points = out['points'];
  if (out['edges'] == null && points is List && points.length >= 3) {
    out['edges'] = closedEdges(points.length);
  }
  return out;
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
