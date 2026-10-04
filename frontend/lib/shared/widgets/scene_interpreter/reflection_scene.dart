import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons, Slider;
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../app_actions.dart';

// =====================================================================
// §轴对称交互讲解渲染器（kind = reflection，ADR-0061 决策 9.1）
//
// 几何严格对齐已验证的 HTML 原型（prototypes/reflection_demo.html）：
// - 折叠角 θ = 进度 × 180°（进度 0..1 ↔ θ 0..π），重合只在 θ=π 判定。
// - 图形按对称轴裁剪成两个填充半区（半平面裁剪），静止侧（青）/ 折叠侧（橙）。
// - 折叠侧变换：Pf = C + u·d + v·cosθ·n（u 沿轴分量不变、v 法向分量按 cosθ 缩放）。
// - 重合判定门控于 θ≈π 且轴为真正对称线（折叠侧 vs 静止侧，禁止与自身反射比对）。
// =====================================================================

/// 预设图形（归一化坐标 0..1，y 向下）。
enum ReflectionFigure { house, kite, arrow, para }

extension ReflectionFigureX on ReflectionFigure {
  /// 图形顶点（归一化）。
  List<Offset> get points {
    switch (this) {
      case ReflectionFigure.house:
        return const [
          Offset(0.30, 0.70),
          Offset(0.70, 0.70),
          Offset(0.70, 0.45),
          Offset(0.50, 0.25),
          Offset(0.30, 0.45),
        ];
      case ReflectionFigure.kite:
        return const [
          Offset(0.50, 0.20),
          Offset(0.72, 0.50),
          Offset(0.50, 0.80),
          Offset(0.28, 0.50),
        ];
      case ReflectionFigure.arrow:
        return const [
          Offset(0.20, 0.42),
          Offset(0.62, 0.42),
          Offset(0.62, 0.30),
          Offset(0.82, 0.50),
          Offset(0.62, 0.70),
          Offset(0.62, 0.58),
          Offset(0.20,0.58),
        ];
      case ReflectionFigure.para:
        return const [
          Offset(0.30, 0.40),
          Offset(0.70, 0.40),
          Offset(0.82, 0.70),
          Offset(0.42, 0.70),
        ];
    }
  }

  /// 该图形默认对称轴角度（度，0=水平、90=竖直）。
  double get defaultAxisAngle {
    switch (this) {
      case ReflectionFigure.house:
      case ReflectionFigure.kite:
      case ReflectionFigure.para:
        return 90;
      case ReflectionFigure.arrow:
        return 0;
    }
  }

  static ReflectionFigure fromName(String? name) => switch (name) {
        'house' => ReflectionFigure.house,
        'kite' => ReflectionFigure.kite,
        'arrow' => ReflectionFigure.arrow,
        'para' => ReflectionFigure.para,
        _ => ReflectionFigure.house,
      };
}

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

/// 轴对称场景数据（与 SceneSpec JSON 解耦，可直接构造以便测试）。
///
/// 由 [ReflectionSceneData.fromSpec] 从 ADR-0061 的 SceneSpec 解析；
/// 缺字段时回退默认值。
class ReflectionSceneData {
  final ReflectionFigure figure;
  final double axisAngle;
  final double axisX;
  final double axisY;
  final bool controlsPlay;
  final bool controlsScrub;
  final String? narrative;
  final bool editable;
  final bool lockedAxisymmetric;

  const ReflectionSceneData({
    required this.figure,
    this.axisAngle = 90,
    this.axisX = 0.5,
    this.axisY = 0.5,
    this.controlsPlay = true,
    this.controlsScrub = true,
    this.narrative,
    this.editable = true,
    this.lockedAxisymmetric = true,
  });

  /// 由 SceneSpec 解析（ADR-0061 §9.1）；缺字段回退默认。
  factory ReflectionSceneData.fromSpec(Map<String, dynamic> spec) {
    final inputs = (spec['inputs'] as List?) ?? <dynamic>[];
    var axisAngle = 90.0;
    var axisX = 0.5;
    var axisY = 0.5;
    var figureName = 'house';
    for (final raw in inputs) {
      final m = raw as Map<String, dynamic>;
      final key = m['key'] as String?;
      final val = m['value'];
      switch (key) {
        case 'axisAngle':
          if (val is num) axisAngle = val.toDouble();
        case 'axisX':
          if (val is num) axisX = val.toDouble();
        case 'axisY':
          if (val is num) axisY = val.toDouble();
        case 'figure':
          if (val is String) figureName = val;
      }
    }
    final controls = spec['controls'] as Map? ?? <String, dynamic>{};
    final outputs = spec['outputs'] as Map? ?? <String, dynamic>{};
    return ReflectionSceneData(
      figure: ReflectionFigureX.fromName(figureName),
      axisAngle: axisAngle,
      axisX: axisX,
      axisY: axisY,
      controlsPlay: controls['play'] as bool? ?? true,
      controlsScrub: controls['scrub'] as bool? ?? true,
      narrative: spec['narrative'] as String?,
      editable: spec['editable'] as bool? ?? true,
      lockedAxisymmetric: outputs['isAxisymmetric'] as bool? ?? true,
    );
  }
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
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _axisAngle = widget.data.axisAngle;
    _axisX = widget.data.axisX;
    _axisY = widget.data.axisY;
    _fold = AnimationController(vsync: this, value: 0)
      ..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant ReflectionSceneWidget old) {
    super.didUpdateWidget(old);
    // 外部（编辑器）修改默认参数时同步内部状态并复位动画，避免预览卡在旧值。
    if (old.data.figure != widget.data.figure ||
        old.data.axisAngle != widget.data.axisAngle ||
        old.data.axisX != widget.data.axisX ||
        old.data.axisY != widget.data.axisY) {
      _axisAngle = widget.data.axisAngle;
      _axisX = widget.data.axisX;
      _axisY = widget.data.axisY;
      _fold.stop();
      _fold.value = 0;
      _playing = false;
      setState(() {});
    }
  }

  @override
  void dispose() {
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
          _axisAngle,
          0,
          180,
          1,
          (v) => setState(() => _axisAngle = v),
          '${_axisAngle.round()}°',
        ),
        _labeledSlider(
          '对称轴水平',
          _axisX,
          0.3,
          0.7,
          0.01,
          (v) => setState(() => _axisX = v),
          _axisX.toStringAsFixed(2),
        ),
        _labeledSlider(
          '对称轴垂直',
          _axisY,
          0.3,
          0.7,
          0.01,
          (v) => setState(() => _axisY = v),
          _axisY.toStringAsFixed(2),
        ),
      ];

  Widget _labeledSlider(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChanged,
    String display,
  ) {
    final t = AppTheme.textOf(context);
    final divisions = ((max - min) / step).round();
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: t.labelSmall!)),
        Expanded(
          // TODO: 替换为 ShadSlider 以贴合设计系统。
          child: Slider(
            value: value,
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
    final points = widget.data.figure.points;
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
                child: Slider(
                  value: _fold.value,
                  // TODO: 替换为 ShadSlider 以贴合设计系统。
                  onChanged: widget.data.controlsScrub ? _scrub : null,
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
