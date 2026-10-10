import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSliderController;

import '../../theme/app_theme.dart';
import '../app_actions.dart';
import '../app_slider.dart';
import 'reflection_scene_data.dart';
import 'reflection_scene_painter.dart';

// =====================================================================
// §轴对称交互讲解渲染器（kind = reflection，ADR-0061 决策 9.1 / ADR-0083 决策 8）
//
// 低层绘制与几何（半平面裁剪 / 折叠变换 / 画家）在 `reflection_scene_painter.dart`
// ——同一份绘制逻辑既服务于**播放态**（本文件），也服务于**编辑态**（画板），
// 故独立成文件（ADR-0058 §2），避免两处各画一套而漂移。
//
// 本文件只做「一份顶点 + 一个 kind 外壳 → 一屏可交互演示」的装配，并承载
// **编辑态手势**（拖顶点 / 移对称轴）。
// =====================================================================

/// 顶点命中半径（归一化画布坐标）：拖动时离哪个顶点最近就抓哪个。
/// 0.06 ≈ 400px 画布上的 24px —— 够手指点中，又不至于一抓抓到隔壁的顶点。
const double _handleHitRadius = 0.06;

/// 对称轴中心的可拖范围（与轴滑块 `min`/`max` 一致）。
/// 必须同域：拖出来的值若越出滑块量程，滑块会显示在边界、与实际轴对不上。
const double _axisDragMin = 0.3;
const double _axisDragMax = 0.7;

/// 轴对称交互演示（kind = reflection）骨架。
///
/// 被动播放：沿内部对称轴对折；主动分析：旋转 / 平移对称轴、改进度，看是否重合。
/// 重合判定严格门控于 180°（ADR-0061 决策 9.1）。
///
/// **同一渲染器 = 播放器 = 画板**（ADR-0083 决策 8）：[editing] 为真即进入编辑态，
/// 画布接受「拖顶点 / 移对称轴」，并在顶点上画可拖手柄；对折播放一件不少。
class ReflectionSceneWidget extends StatefulWidget {
  final ReflectionSceneData data;

  /// 轴参数变更回调（编辑器语境）：用户拖动任一个轴滑块即触发，便于父级把当前轴
  /// 写回自己的状态（如弹窗关闭后仍能按调过的轴保存默认讲解模板）。儿童 / 普通预览
  /// 不传，无副作用。
  final void Function(double angle, double x, double y)? onAxisChanged;

  /// **编辑态**：画布接受手势（拖顶点改几何 / 拖空白处移对称轴），顶点上画手柄，
  /// 且**不再显示「是不是轴对称」的结论**（ADR-0083 决策 2：判定交给眼睛，作者也不
  /// 预判——否则作者会照着结论去微调顶点，把「亲手看」这件事跳过去）。
  final bool editing;

  /// 顶点变更回调（编辑态）：用户拖动某个顶点后回传整份新顶点（父级据此保存）。
  final ValueChanged<List<Offset>>? onPointsChanged;

  const ReflectionSceneWidget({
    super.key,
    required this.data,
    this.onAxisChanged,
    this.editing = false,
    this.onPointsChanged,
  });

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

  /// 编辑态的顶点（本地即时反馈用；外部改几何时由 didUpdateWidget 重新同步）。
  late List<Offset> _editPoints;

  /// 正在拖的顶点索引；null = 没在拖顶点（可能正拖对称轴）。
  int? _dragVertex;

  /// 是否正拖着对称轴中心。
  bool _dragAxis = false;

  @override
  void initState() {
    super.initState();
    _axisAngle = widget.data.axisAngle;
    _axisX = widget.data.axisX;
    _axisY = widget.data.axisY;
    _editPoints = List<Offset>.of(widget.data.points);
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
      // 折叠过程，太慢会让儿童等得不耐烦。reduce-motion 下 `_play()` 直接跳到
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
    // 外部（编辑器 / 画板预设）改了顶点就重新同步编辑态副本。用 listEquals 判等：
    // 若父级只是把我们刚回调的顶点原样传回（回显），这里不会误清掉本地拖拽。
    if (!listEquals(old.data.points, widget.data.points) &&
        !listEquals(_editPoints, widget.data.points)) {
      _editPoints = List<Offset>.of(widget.data.points);
    }
    // 外部（编辑器）修改默认参数时同步内部状态并复位动画，避免预览卡在旧值。
    // 几何按 points 比对（ADR-0061 §O 顶点驱动）：图形换了 = 顶点变了。
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

  /// 当前生效的顶点：编辑态用本地副本（即时反馈），否则用外部下发的几何。
  List<Offset> get _activePoints =>
      widget.editing ? _editPoints : widget.data.points;

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

  /// 任一轴滑块变动后写回父级（编辑器弹出语境下让弹窗关闭后仍能按调过的轴保存）。
  void _emitAxis() =>
      widget.onAxisChanged?.call(_axisAngle, _axisX, _axisY);

  // —— 编辑态手势（ADR-0083 决策 8）——
  //
  // 画布上的拖拽不是「可点区域」（它没有离散的点击语义、也就不该进 Tab 焦点树），
  // 故这里用裸 `GestureDetector`；按钮类可点区仍一律走 AppFocusableAction（ADR-0046）。

  /// 画布本地坐标 → 归一化 0..1（夹紧，避免拖出画布外）。
  Offset _toNormalized(Offset local, double side) => Offset(
        (local.dx / side).clamp(0.0, 1.0),
        (local.dy / side).clamp(0.0, 1.0),
      );

  void _onPanDown(Offset local, double side) {
    final p = _toNormalized(local, side);
    // 先找命中半径内最近的顶点；没命中就当作「拖对称轴中心」。
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < _editPoints.length; i++) {
      final d = (_editPoints[i] - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best >= 0 && bestD <= _handleHitRadius) {
      _dragVertex = best;
      _dragAxis = false;
    } else {
      _dragVertex = null;
      _dragAxis = true;
    }
  }

  void _onPanUpdate(Offset local, double side) {
    final p = _toNormalized(local, side);
    if (_dragVertex != null) {
      final next = List<Offset>.of(_editPoints);
      next[_dragVertex!] = p;
      setState(() => _editPoints = next);
      widget.onPointsChanged?.call(next);
      return;
    }
    if (_dragAxis) {
      final nx = p.dx.clamp(_axisDragMin, _axisDragMax);
      final ny = p.dy.clamp(_axisDragMin, _axisDragMax);
      setState(() {
        _axisX = nx;
        _axisY = ny;
      });
      _axisXC.value = nx;
      _axisYC.value = ny;
      _emitAxis();
    }
  }

  void _onPanEnd() {
    _dragVertex = null;
    _dragAxis = false;
  }

  List<Widget> _axisControls() => [
        const SizedBox(height: AppSpacing.sm),
        _labeledSlider(
          '对称轴角度',
          _axisAngleC,
          0,
          180,
          (v) {
            setState(() => _axisAngle = v);
            _emitAxis();
          },
          '${_axisAngle.round()}°',
        ),
        _labeledSlider(
          '对称轴水平',
          _axisXC,
          0.3,
          0.7,
          (v) {
            setState(() => _axisX = v);
            _emitAxis();
          },
          _axisX.toStringAsFixed(2),
        ),
        _labeledSlider(
          '对称轴垂直',
          _axisYC,
          0.3,
          0.7,
          (v) {
            setState(() => _axisY = v);
            _emitAxis();
          },
          _axisY.toStringAsFixed(2),
        ),
      ];

  Widget _labeledSlider(
    String label,
    ShadSliderController controller,
    double min,
    double max,
    ValueChanged<double>? onChanged,
    String display,
  ) {
    final t = AppTheme.textOf(context);
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: t.labelSmall!)),
        Expanded(
          child: AppSlider(
            controller: controller,
            min: min,
            max: max,
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
    // 编辑态不给结论（ADR-0083 决策 2）：只报对折进度，重合与否由作者自己看。
    if (widget.editing) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        ),
        child: Text(
          atEnd
              ? '对折到 180° —— 自己看两侧是否完全重合'
              : '对折进行中（$deg°）；拖顶点改图形，拖空白处移动对称轴',
          style: t.labelMedium!.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }
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
    final points = _activePoints;
    final symmetric = isAxisymmetric(points, c, d, n);
    final progressDeg = (_fold.value * 180).round();
    final atEnd = _fold.value >= 0.99;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            final side = constraints.maxWidth;
            final canvas = SizedBox(
              width: side,
              height: side,
              child: CustomPaint(
                painter: ReflectionScenePainter(
                  points: points,
                  edges: widget.data.edges,
                  c: c,
                  d: d,
                  n: n,
                  theta: _fold.value * math.pi,
                  axisAngle: _axisAngle,
                  axisX: _axisX,
                  axisY: _axisY,
                  showHandles: widget.editing,
                ),
              ),
            );
            if (!widget.editing) return canvas;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (dd) => _onPanDown(dd.localPosition, side),
              onPanUpdate: (dd) => _onPanUpdate(dd.localPosition, side),
              onPanEnd: (_) => _onPanEnd(),
              onPanCancel: _onPanEnd,
              child: canvas,
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
        if (widget.data.showAxisControls) ..._axisControls(),
        if (widget.data.narrative != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(widget.data.narrative!, style: AppTheme.textOf(context).bodySmall!),
        ],
      ],
    );
  }
}
