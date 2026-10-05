import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSliderController;

import '../../theme/app_theme.dart';
import '../app_actions.dart';
import '../app_slider.dart';
import 'reflection_scene_data.dart';

// =====================================================================
// §轴对称交互讲解渲染器（kind = reflection，ADR-0061 决策 9.1）
//
// 几何严格对齐已验证的 HTML 原型（prototypes/reflection_demo.html）：
// - 折叠角 θ = 进度 × 180°（进度 0..1 ↔ θ 0..π），重合只在 θ=π 判定。
// - 图形按对称轴裁剪成两个填充半区（半平面裁剪），静止侧（青）/ 折叠侧（橙）。
// - 折叠侧变换：Pf = C + u·d + v·cosθ·n（u 沿轴分量不变、v 法向分量按 cosθ 缩放）。
// - 重合判定门控于 θ≈π 且轴为真正对称线（折叠侧 vs 静止侧，禁止与自身反射比对）。
// =====================================================================

/// 预设图形已移出本文件 → `shared/domain/figures.dart`（ADR-0061 §O）。
///
/// 本渲染器**不再认识「房子/风筝」这类概念**，只吃一组顶点（ADR-0061 §O）：
/// 图形数据是教学素材（见 `figures.dart`），由后端按题目选项下发或由内置预设兜底。
/// `ReflectionFigure` / `ReflectionFigureX` 仅作为**兜底预设集**保留给教师调参
/// 面板与「spec 未带points」的旧数据。

/// 重合判定阈值（归一化空间）。
const double _coincidenceThreshold = 0.03;

/// 半平面裁剪：保留 (P−C)·n × keepSign ≥ 0 的一侧
///（keepSign=+1 保留 v≥0 折叠侧；−1 保留 v≤0 静止侧）。
List<Offset> _clipHalfPlane(
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
Offset _foldVertex(Offset p, Offset c, Offset d, Offset n, double theta) {
  final u = (p.dx - c.dx) * d.dx + (p.dy - c.dy) * d.dy;
  final v = (p.dx - c.dx) * n.dx + (p.dy - c.dy) * n.dy;
  final nf = v * math.cos(theta);
  return Offset(c.dx + u * d.dx + nf * n.dx, c.dy + u * d.dy + nf * n.dy);
}

/// 是否轴对称：所有顶点关于当前轴（θ=π）反射后，均能在原顶点集中找到
/// 最近距离 < 阈值的匹配（折叠侧 vs 静止侧比对，非与自身反射比对）。
bool _isAxisymmetric(List<Offset> poly, Offset c, Offset d, Offset n) {
  for (final p in poly) {
    final r = _foldVertex(p, c, d, n, math.pi);
    final hit = poly.any((q) => (r - q).distance < _coincidenceThreshold);
    if (!hit) return false;
  }
  return true;
}

class _ReflectionPainter extends CustomPainter {
  final List<Offset> points;
  final Offset c;
  final Offset d;
  final Offset n;
  final double theta;
  final double axisAngle;
  final double axisX;
  final double axisY;

  const _ReflectionPainter({
    required this.points,
    required this.c,
    required this.d,
    required this.n,
    required this.theta,
    required this.axisAngle,
    required this.axisX,
    required this.axisY,
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
    final stat = _clipHalfPlane(points, c, n, -1);
    final fold = _clipHalfPlane(points, c, n, 1);
    final foldT = fold.map((p) => _foldVertex(p, c, d, n, theta)).toList();

    // 参考轮廓（始终可见，虚线低透明）。
    _poly(
      canvas,
      size,
      points,
      stroke: AppBrutal.ink.withValues(alpha: 0.4),
      strokeWidth: AppElevation.borderWidthHairline,
    );
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
  }

  @override
  bool shouldRepaint(_ReflectionPainter old) =>
      old.theta != theta ||
      old.axisAngle != axisAngle ||
      old.axisX != axisX ||
      old.axisY != axisY ||
      old.points != points;
}


/// 轴对称交互演示（kind = reflection）骨架。
///
/// 被动播放：沿内部对称轴对折；主动分析：旋转 / 平移对称轴、改进度，看是否重合。
/// 重合判定严格门控于 180°（ADR-0061 决策 9.1）。
class ReflectionSceneWidget extends StatefulWidget {
  final ReflectionSceneData data;

  const ReflectionSceneWidget({super.key, required this.data});

  @override
  State<ReflectionSceneWidget> createState() => _ReflectionSceneWidgetState();
}

class _ReflectionSceneWidgetState extends State<ReflectionSceneWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fold;
  late double _axisAngle;
  late double _axisX;
  late double _axisY;
  // 滑块改用 shadcn_ui 的 `ShadSlider`（设计系统，ADR-0044），它是**无受控**组件，
  // 当前值托管在 `ShadSliderController` 上；下面四个控制器与上面的状态变量双向同步：
  // 拖拽由 ShadSlider 写回控制器并经 onChanged 写回变量；外部重置（didUpdateWidget）
  // 改写变量后须同步 `.value`，否则滑块卡在旧值。
  late final ShadSliderController _axisAngleC;
  late final ShadSliderController _axisXC;
  late final ShadSliderController _axisYC;
  late final ShadSliderController _foldC;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _axisAngle = widget.data.axisAngle;
    _axisX = widget.data.axisX;
    _axisY = widget.data.axisY;
    _axisAngleC = ShadSliderController(initialValue: _axisAngle);
    _axisXC = ShadSliderController(initialValue: _axisX);
    _axisYC = ShadSliderController(initialValue: _axisY);
    _foldC = ShadSliderController(initialValue: 0);
    _fold = AnimationController(
      vsync: this,
      value: 0,
      // 必须给 duration：`_play()` 走 `forward()`，没设 duration 会在点击播放时
      // 抛 "AnimationController.forward() called with no default duration"。
      // 取值对着 spec 的「速度」语义：一次完整对折（0→180°）1.4s，太快看不清
      // 折叠过程，太慢会让学生等得不耐烦。reduce-motion 下 `_play()` 直接跳到
      // 终点、根本不走动画（见 `_play`），所以这个时长不影响无障碍用户。
      duration: const Duration(milliseconds: 1400),
    )..addListener(() {
        // 播放动画时 `_fold.value` 每帧变化，同步给滑块控制器使其跟随。
        _foldC.value = _fold.value;
        setState(() {});
      });
  }

  @override
  void didUpdateWidget(covariant ReflectionSceneWidget old) {
    super.didUpdateWidget(old);
    // 外部（编辑器）修改默认参数时同步内部状态并复位动画，避免预览卡在旧值。
    // 几何按points 比对（ADR-0061 §O 顶点驱动）：图形换了 = 顶点变了。
    if (!listEquals(old.data.points, widget.data.points) ||
        old.data.axisAngle != widget.data.axisAngle ||
        old.data.axisX != widget.data.axisX ||
        old.data.axisY != widget.data.axisY) {
      _axisAngle = widget.data.axisAngle;
      _axisX = widget.data.axisX;
      _axisY = widget.data.axisY;
      _axisAngleC.value = _axisAngle;
      _axisXC.value = _axisX;
      _axisYC.value = _axisY;
      _fold.stop();
      _fold.value = 0;
      _foldC.value = 0;
      _playing = false;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _axisAngleC.dispose();
    _axisXC.dispose();
    _axisYC.dispose();
    _foldC.dispose();
    _fold.dispose();
    super.dispose();
  }

  (Offset, Offset, Offset) get _frame {
    final a = _axisAngle * math.pi / 180;
    final c = Offset(_axisX, _axisY);
    final d = Offset(math.cos(a), math.sin(a));
    final n = Offset(-math.sin(a), math.cos(a));
    return (c, d, n);
  }

  void _play() {
    // 减弱动画：直接呈现完全折叠态，保留交互。
    if (reducedMotionOf(context)) {
      _fold.value = 1;
      return;
    }
    if (_fold.value >= 1) _fold.value = 0;
    _playing = true;
    _fold.forward().then((_) => _playing = false);
  }

  void _pause() {
    _fold.stop();
    _playing = false;
    setState(() {});
  }

  void _scrub(double v) {
    _fold.stop();
    _playing = false;
    _fold.value = v;
  }

  List<Widget> _axisControls() => [
        const SizedBox(height: AppSpacing.sm),
        _labeledSlider(
          '对称轴角度',
          _axisAngleC,
          0,
          180,
          1,
          (v) => setState(() => _axisAngle = v),
          '${_axisAngle.round()}°',
        ),
        _labeledSlider(
          '对称轴水平',
          _axisXC,
          0.3,
          0.7,
          0.01,
          (v) => setState(() => _axisX = v),
          _axisX.toStringAsFixed(2),
        ),
        _labeledSlider(
          '对称轴垂直',
          _axisYC,
          0.3,
          0.7,
          0.01,
          (v) => setState(() => _axisY = v),
          _axisY.toStringAsFixed(2),
        ),
      ];

  Widget _labeledSlider(
    String label,
    ShadSliderController controller,
    double min,
    double max,
    double step,
    ValueChanged<double>? onChanged,
    String display,
  ) {
    final t = AppTheme.textOf(context);
    final divisions = ((max - min) / step).round();
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: t.labelSmall!)),
        Expanded(
          child: AppSlider(
            controller: controller,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 44, child: Text(display, style: t.labelSmall!)),
      ],
    );
  }

  Widget _statusRow(bool symmetric, bool atEnd, int deg) {
    final colors = AppTheme.colorsOf(context);
    final t = AppTheme.textOf(context);
    final ok = atEnd && symmetric;
    final bad = atEnd && !symmetric;
    final text = ok
        ? '✓ 对折 180°：折叠侧完全盖住静止侧 —— 是轴对称图形'
        : bad
            ? '✗ 对折 180°：折叠侧无法盖住静止侧 —— 该轴不是对称轴'
            : '对折进行中（$deg°），仅到 180° 才能判断是否重合';
    final fg = ok
        ? colors.semanticPositiveFg
        : bad
            ? colors.semanticErrorFg
            : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: ok
            ? colors.semanticPositive
            : bad
                ? colors.semanticError
                : colors.surfaceContainer,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
      ),
      child: Text(text, style: t.labelMedium!.copyWith(color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (c, d, n) = _frame;
    final points = widget.data.points;
    final symmetric = _isAxisymmetric(points, c, d, n);
    final progressDeg = (_fold.value * 180).round();
    final atEnd = _fold.value >= 0.99;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            final side = constraints.maxWidth;
            return SizedBox(
              width: side,
              height: side,
              child: CustomPaint(
                painter: _ReflectionPainter(
                  points: points,
                  c: c,
                  d: d,
                  n: n,
                  theta: _fold.value * math.pi,
                  axisAngle: _axisAngle,
                  axisX: _axisX,
                  axisY: _axisY,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _statusRow(symmetric, atEnd, progressDeg),
        if (widget.data.controlsPlay) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              AppIconAction(
                icon: _playing ? Icons.pause : Icons.play_arrow,
                onPressed: _playing ? _pause : _play,
                semanticLabel: _playing ? '暂停对折' : '播放对折',
              ),
              Expanded(
                child: AppSlider(
                  controller: _foldC,
                  onChanged: widget.data.controlsScrub ? _scrub : null,
                  enabled: widget.data.controlsScrub,
                  label: '对折 $progressDeg°',
                ),
              ),
            ],
          ),
        ],
        if (widget.data.editable) ..._axisControls(),
        if (widget.data.narrative != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(widget.data.narrative!, style: AppTheme.textOf(context).bodySmall!),
        ],
      ],
    );
  }
}
