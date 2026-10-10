// §图库解析（ADR-0083 决策 1/7）
//
// 图库的几何事实源在 DB（`figure_library` 表），行只有几何：
// `{key, label, points[[x,y]], edges[[i,j]], note, is_builtin}`——**不含任何 axis 属性**
// （决策 2：对称靠拖轴 + 翻转视觉判定，图库不再断言轴数与轴向）。
//
// 为什么解析不写进 `figures.dart`：后者是 `gen_figures.py` 的**构建期产物**
// （T06 退役），手写内容会被生成器覆盖、也会打破 parity 锁。图库解析是运行时代码，
// 必须独立成文件。
library;

import '../utils/json_decode.dart';
import 'figures.dart';

/// 图库行的顶点解析：`[[x,y],…]` → 归一化顶点。坏行**跳过坏点**而不是整体丢弃。
List<({double x, double y})> _verticesOf(Object? points) {
  final out = <({double x, double y})>[];
  if (points is List) {
    for (final p in points) {
      if (p is! List || p.length < 2) continue;
      final x = (p[0] as num?)?.toDouble();
      final y = (p[1] as num?)?.toDouble();
      if (x == null || y == null) continue;
      out.add((x: x, y: y));
    }
  }
  return out;
}

/// 内置图形缺省时的轴初值。
///
/// 图库**不存轴**（ADR-0083 决策 2/8），故这里只能给一个中性值：90°（reflection
/// 外壳的竖轴初值）。真正打开演示时轴初值取自 kind 外壳
/// （[ReflectionSceneData.axisAngle]），不看这个字段——它只服务缩略图那条纯装饰的
/// 虚线（调用方可传 `axisAngle` 覆盖成外壳的值）。
const double kLibraryDefaultAxisAngle = 90;

/// 一条图库行 → 画廊 / 画板可直接渲染的 [FigureShape]。
///
/// 顶点不足 3 个（画不出多边形）或 `key` 为空 → 返回 null，由调用方跳过：
/// 图库里出现一条渲染不出来的空行，会让用户「明明存了却找不到」，不如不显示。
FigureShape? figureShapeFromLibraryJson(Map<String, dynamic> json) {
  final key = json['key'] as String?;
  if (key == null || key.isEmpty) return null;
  final vertices = _verticesOf(json['points']);
  if (vertices.length < 3) return null;
  return FigureShape(
    key: key,
    label: json['label'] as String? ?? key,
    vertices: vertices,
    defaultAxisAngle: kLibraryDefaultAxisAngle,
    // 图库不再存轴数/轴向（ADR-0083 决策 2）：空表 = 「图库不表态」。
    // 依赖它的旧路径（如「有几条对称轴」）改由题目答案字段或纯视觉演示承担。
    axisAngles: const <double>[],
  );
}

/// `GET /scene-library/figures` 响应体 → 图形列表。
///
/// 响应形状 `{figures: [ … ]}`（后端 `FigureLibraryResp`）。不是对象 / `figures`
/// 不是数组 → 抛 [FormatException]（`decodeMap` 的口径：类型错误不甩给上层）。
List<FigureShape> parseFigureLibrary(Object data) {
  final raw = decodeMap(data)['figures'];
  if (raw is! List) return const <FigureShape>[];
  final out = <FigureShape>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final shape = figureShapeFromLibraryJson(Map<String, dynamic>.from(e));
    if (shape != null) out.add(shape);
  }
  return out;
}
