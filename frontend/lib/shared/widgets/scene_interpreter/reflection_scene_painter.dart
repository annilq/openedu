import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

// =====================================================================
// §轴对称演示的低层绘制 / 几何（ADR-0061 决策 9.1）
//
// 从 `reflection_scene.dart` 拆出（ADR-0058 §2：一个文件一个职责）——同一份绘制逻辑
// 既被**播放态**（ReflectionSceneWidget）用，也被**编辑态**（画板）用，故独立成文件、
// 以公开类型暴露，避免两处各画一套而漂移。
//
// 几何严格对齐已验证的 HTML 原型（prototypes/reflection_demo.html）：
// - 折叠角 θ = 进度 × 180°（进度 0..1 ↔ θ 0..π），重合只在 θ=π 判定。
// - 图形按对称轴裁剪成两个填充半区（半平面裁剪），静止侧（青）/ 折叠侧（橙）。
// - 折叠侧变换：Pf = C + u·d + v·cosθ·n（u 沿轴分量不变、v 法向分量按 cosθ 缩放）。
// =====================================================================

/// 重合判定阈值（归一化空间）。
const double reflectionCoincidenceThreshold = 0.03;

/// 半平面裁剪：保留 (P−C)·n × keepSign ≥ 0 的一侧
///（keepSign=+1 保留 v≥0 折叠侧；−1 保留 v≤0 静止侧）。
List<Offset> clipHalfPlane(
  List<Offset> poly,
  Offset c,
  Offset n,
  double keepSign,
) {
  final out = <Offset>[];
  final count = poly.length;
  for (var i = 0; i < count; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % count];
    final va = (a.dx - c.dx) * n.dx + (a.dy - c.dy) * n.dy;
    final vb = (b.dx - c.dx) * n.dx + (b.dy - c.dy) * n.dy;
    final ain = va * keepSign >= -1e-9;
    final bin = vb * keepSign >= -1e-9;
    if (ain) out.add(a);
    if (ain != bin) {
      final t = va / (va - vb);
      out.add(Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy)));
    }
  }
  return out;
}

/// 折叠顶点：Pf = C + u·d + v·cosθ·n。
Offset foldVertex(Offset p, Offset c, Offset d, Offset n, double theta) {
  final u = (p.dx - c.dx) * d.dx + (p.dy - c.dy) * d.dy;
  final v = (p.dx - c.dx) * n.dx + (p.dy - c.dy) * n.dy;
  final nf = v * math.cos(theta);
  return Offset(c.dx + u * d.dx + nf * n.dx, c.dy + u * d.dy + nf * n.dy);
}

/// 是否轴对称：所有顶点关于当前轴（θ=π）反射后，均能在原顶点集中找到
/// 最近距离 < 阈值的匹配（折叠侧 vs 静止侧比对，非与自身反射比对）。
bool isAxisymmetric(List<Offset> poly, Offset c, Offset d, Offset n) {
  for (final p in poly) {
    final r = foldVertex(p, c, d, n, math.pi);
    final hit = poly.any(
      (q) => (r - q).distance < reflectionCoincidenceThreshold,
    );
    if (!hit) return false;
  }
  return true;
}

/// 由轴角度 / 位置算正交基：中心 c、轴向单位向量 d、法向单位向量 n。
(Offset, Offset, Offset) reflectionFrame(double angleDeg, double x, double y) {
  final a = angleDeg * math.pi / 180;
  return (Offset(x, y), Offset(math.cos(a), math.sin(a)), Offset(-math.sin(a), math.cos(a)));
}

/// 轴对称演示画笔画：静止侧（青）/ 折叠侧（橙）+ 参考轮廓 + 对称轴虚线。
///
/// [showHandles] 为真时在**每个顶点**画一个可拖手柄（画板编辑态用）——播放态不画，
/// 免得学生以为那是一个可点的 UI 元素。
class ReflectionScenePainter extends CustomPainter {
  final List<Offset> points;

  /// 顶点连接关系（索引对）；null/空 = 按顶点顺序闭合（ADR-0083 决策 5）。
  final List<List<int>>? edges;
  final Offset c;
  final Offset d;
  final Offset n;
  final double theta;
  final double axisAngle;
  final double axisX;
  final double axisY;

  /// 是否在顶点上画可拖手柄（编辑态）。默认 false（播放态干净）。
  final bool showHandles;

  const ReflectionScenePainter({
    required this.points,
    this.edges,
    required this.c,
    required this.d,
    required this.n,
    required this.theta,
    required this.axisAngle,
    required this.axisX,
    required this.axisY,
    this.showHandles = false,
  });

  void _poly(
    Canvas canvas,
    Size size,
    List<Offset> poly, {
    Color? fill,
    Color? stroke,
    double strokeWidth = 0,
  }) {
    if (poly.length < 3) return;
    final path = Path();
    for (var i = 0; i < poly.length; i++) {
      final p = Offset(poly[i].dx * size.width, poly[i].dy * size.height);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    if (fill != null) {
      canvas.drawPath(path, Paint()..color = fill..style = PaintingStyle.fill);
    }
    if (stroke != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _dashed(Canvas canvas, Offset p1, Offset p2, Color color, double width) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    const dash = 8.0;
    const gap = 5.0;
    final ux = dx / len;
    final uy = dy / len;
    final steps = (len / (dash + gap)).floor();
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < steps; i++) {
      final s = i * (dash + gap);
      canvas.drawLine(
        Offset(p1.dx + ux * s, p1.dy + uy * s),
        Offset(p1.dx + ux * (s + dash), p1.dy + uy * (s + dash)),
        paint,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stat = clipHalfPlane(points, c, n, -1);
    final fold = clipHalfPlane(points, c, n, 1);
    final foldT = fold.map((p) => foldVertex(p, c, d, n, theta)).toList();

    // 参考轮廓（始终可见，虚线低透明）。按 edges 逐段描边——默认闭合的简单多边形
    // 与旧行为逐点一致；带自定义连接时（开折线 / 多部件）如实画出（ADR-0083 §5）。
    final outline = Paint()
      ..color = AppBrutal.ink.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppElevation.borderWidthHairline
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (edges != null && edges!.isNotEmpty) {
      for (final e in edges!) {
        if (e.length < 2) continue;
        final i = e[0];
        final j = e[1];
        if (i < 0 || j < 0 || i >= points.length || j >= points.length) continue;
        canvas.drawLine(
          Offset(points[i].dx * size.width, points[i].dy * size.height),
          Offset(points[j].dx * size.width, points[j].dy * size.height),
          outline,
        );
      }
    } else {
      _poly(
        canvas,
        size,
        points,
        stroke: AppBrutal.ink.withValues(alpha: 0.4),
        strokeWidth: AppElevation.borderWidthHairline,
      );
    }
    // 静止侧（青）。
    _poly(
      canvas,
      size,
      stat,
      fill: AppBrutal.cyan.withValues(alpha: 0.35),
      stroke: AppBrutal.ink,
      strokeWidth: AppElevation.borderWidth,
    );
    // 折叠侧（橙，覆盖在上）。
    _poly(
      canvas,
      size,
      foldT,
      fill: AppBrutal.orange.withValues(alpha: 0.55),
      stroke: AppBrutal.ink,
      strokeWidth: AppElevation.borderWidth,
    );

    // 对称轴（虚线）。
    const l = 0.46;
    final a1 = Offset(
      (c.dx - l * d.dx) * size.width,
      (c.dy - l * d.dy) * size.height,
    );
    final a2 = Offset(
      (c.dx + l * d.dx) * size.width,
      (c.dy + l * d.dy) * size.height,
    );
    _dashed(canvas, a1, a2, AppBrutal.ink, AppElevation.borderWidth);

    // 顶点手柄（编辑态）：让学生 / 教师看见「这几个点可以拖」。
    if (showHandles) {
      final fill = Paint()..color = AppBrutal.paper;
      final ring = Paint()
        ..color = AppBrutal.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppElevation.borderWidth;
      for (final p in points) {
        final o = Offset(p.dx * size.width, p.dy * size.height);
        canvas.drawCircle(o, 6, fill);
        canvas.drawCircle(o, 6, ring);
      }
    }
  }

  @override
  bool shouldRepaint(ReflectionScenePainter old) =>
      old.theta != theta ||
      old.axisAngle != axisAngle ||
      old.axisX != axisX ||
      old.axisY != axisY ||
      old.showHandles != showHandles ||
      old.points != points ||
      !listEquals(old.edges, edges);
}
