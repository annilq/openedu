// §轴对称教学图形模型（ADR-0061 §O / ADR-0083 决策 2/7）
//
// 几何的**事实源在 DB**（`figure_library` 表）。本文件不再是「后端常量的构建期生成
// 产物」——`gen_figures.py` 与前后端 parity 锁已随 ADR-0083 退役（前端改为创作 UI
// 打开时按需 `GET /materials/scene-library/figures`，见 `figureLibraryProvider`）。
//
// 本文件只剩两样东西：
// 1. [FigureShape] —— 渲染层消费的图形模型（画廊 / 画板 / 编辑器 / 选项组共用）；
// 2. [kFallbackFigure] —— **极端兜底**：场景既无内联顶点、又无显式预设时用的一个
//    形状，避免出现空场景（ADR-0083 决策 7「`house` 仅作最后兜底」）。
//
// ⚠️ 需要「一批图形」（画廊 / 画板工具栏 / 挑图形）一律走 `figureLibraryProvider`，
// **不要往本文件加常量**——那正是本轮退役掉的双源。
//
// ⚠️ 图形**不带任何 axis 属性**（决策 2）：对称判定是纯视觉（拖轴 + 翻转演示），
// 图库与模型都不存 authored 轴值。用户交互的轴**初值**属 kind 交互外壳（见
// `scene_shells.dart`）。
library;

import 'dart:ui' show Offset;

/// 一个轴对称教学图形：身份键 + 中文名 + 归一化顶点 + 连接关系。
///
/// 与后端 `Figure`（`app/domain/figures.py`）**同构**：`{key, label, points, edges}`
/// （ADR-0091 决策 3——补 `edges` 就是为消灭「前端只有顶点、按序闭合」这个差异）。
/// **无 axis 属性**（ADR-0083 决策 2）。
///
/// 身份与渲染的分工（ADR-0083 决策 6 收窄）：`key` **只**用于身份 / 溯源 / 校验
/// （画廊角标映射、选中高亮、去重），**渲染只吃 [vertices] / [edges]**：不按 key
/// 回查图库，运行时零图库依赖（决策 7 不动）。
class FigureShape {
  /// 图形标识（后端下发的稳定 key，不是给用户看的名字）。
  final String key;

  /// 图形中文名（仅用于界面标签与题面识别，不参与渲染判定）。
  final String label;

  /// 归一化顶点（x, y∈0..1，y 向下）。
  final List<({double x, double y})> vertices;

  /// 顶点连接关系（顶点索引对）。null / 空 = 按顶点顺序闭合（简单多边形默认）。
  final List<List<int>>? edges;

  const FigureShape({
    required this.key,
    required this.label,
    required this.vertices,
    this.edges,
  });
}

/// 顶点顺序闭合的边集（简单多边形的默认连接）。
///
/// 放在 domain 而不是渲染层：图形模型自己要能给出「缺省连接关系」，否则每个解析
/// 入口（场景规格 / 图库行）都得各写一份闭合逻辑。
List<List<int>> closedEdges(int n) =>
    [for (var i = 0; i < n; i++) [i, (i + 1) % n]];

/// 最后兜底图形（房子）——**只在场景没有任何几何可用时**才画它。
///
/// 为什么留着它：`SceneSpec` 理论上总能自带 `points`，但历史快照 / 手工构造的
/// spec 可能没有；渲染器宁可画一个中性图形，也不要给学生一块空白画布。
/// 它**不是**图库、不是可选清单、也不该被用来「按 key 回查几何」——那是双源。
const FigureShape kFallbackFigure = FigureShape(
  key: 'house',
  label: '房子',
  vertices: <({double x, double y})>[
    (x: 0.30, y: 0.70),
    (x: 0.70, y: 0.70),
    (x: 0.70, y: 0.45),
    (x: 0.50, y: 0.25),
    (x: 0.30, y: 0.45),
  ],
  edges: <List<int>>[
    <int>[0, 1],
    <int>[1, 2],
    <int>[2, 3],
    <int>[3, 4],
    <int>[4, 0],
  ],
);

/// 顶点逐点比对的容差（归一化 0..1 坐标；1e-6 远小于一个像素）。
const double kVertexEpsilon = 1e-6;

/// 在 [library] 里按顶点逐点找回「同一个图形」；找不到返回 null。
///
/// 为什么还需要它：`SceneSpec` 现在**带** `figure.key`（ADR-0091 决策 2 把 ADR-0083
/// 决策 6 从「不含 key」收窄为「渲染不消费 key」），但**存量 / 手写的 spec 仍可能没有
/// key**，而图库行只有 key/label/几何。要回显「教师现在配的是哪一张卡」（编辑器选中态）
/// 就还得拿顶点反查图库。有 key 的场合一律**优先用 key**，别再走顶点。
///
/// 找不到是**正常情况**，不是错误：教师可能在画板里画了库外图形，或图库还没拉回来
/// （运行时零图库依赖，图库只在创作 UI 按需取）。调用方据此当作「未知图形」处理，
/// 不要臆造一个名字或兜到某个内置图形上。
FigureShape? figureMatchingVertices(
  Iterable<FigureShape> library,
  List<Offset> points,
) {
  for (final f in library) {
    if (f.vertices.length != points.length) continue;
    var same = true;
    for (var i = 0; i < points.length; i++) {
      if ((f.vertices[i].x - points[i].dx).abs() > kVertexEpsilon ||
          (f.vertices[i].y - points[i].dy).abs() > kVertexEpsilon) {
        same = false;
        break;
      }
    }
    if (same) return f;
  }
  return null;
}
