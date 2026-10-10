// §图库解析（ADR-0083 决策 1/7）
//
// 图库的几何事实源在 DB（`figure_library` 表），行只有几何：
// `{key, label, points[[x,y]], edges[[i,j]], note, is_builtin}`——**不含任何 axis 属性**
// （决策 2：对称靠拖轴 + 翻转视觉判定，图库不再断言轴数与轴向）。
//
// 为什么解析独立成文件：`figures.dart` 只放**渲染模型 + 极端兜底常量**（它已不再
// 是从后端常量构建期生成的副本）；「DB 行 → 模型」的解析属取数侧，分开更好维护。
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

/// 一条图库行 → 画廊 / 画板可直接渲染的 [FigureShape]。
///
/// 顶点不足 3 个（画不出多边形）或 `key` 为空 → 返回 null，由调用方跳过：
/// 图库里出现一条渲染不出来的空行，会让用户「明明存了却找不到」，不如不显示。
///
/// 图库行只有几何：`points` 是唯一事实，**没有任何 axis 属性**（ADR-0083 决策 2）
/// ——对称判定靠用户拖轴 + 翻转自己看，图库不表态。
FigureShape? figureShapeFromLibraryJson(Map<String, dynamic> json) {
  final key = json['key'] as String?;
  if (key == null || key.isEmpty) return null;
  final vertices = _verticesOf(json['points']);
  if (vertices.length < 3) return null;
  return FigureShape(
    key: key,
    label: json['label'] as String? ?? key,
    vertices: vertices,
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
