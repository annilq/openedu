import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 轻量运动组件，服务于「直率 / 有力 / 明朗」的情绪目标（见 .impeccable.md）。
///
/// 约定（ADR-0044）：
/// - 一律只动 `transform + opacity`（GPU 合成），不触发布局/绘制重排。
/// - **弹跳一律走 [AppSprings] 物理弹簧**，不再用 `Curves.easeOutBack`——后者是
///   三次贝塞尔近似，所有元素共用同一条曲线会「齐步走」，没有质量差异、显得廉价。
/// - 尊重系统减弱动画设置：`MediaQuery.disableAnimations == true` 时退化为静态，
///   但**手势回调必须保留**——历史上在减弱动画分支里直接 `return child`，把
///   `GestureDetector` 一起丢了，按钮会点不动。

/// 判断系统是否「减弱动态效果」。
bool reducedMotionOf(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// 弹簧入场：缩放 + 淡入，一次执行（initState 触发，不随重建重放）。
/// 用于成就图标、结果卡片、首页 Banner 等「登场」时刻。
///
/// 时长由 [spring] 的物理参数决定（阻尼比 ≈0.73，轻微超调），不再接受
/// `Duration`——固定时长表达不了弹簧的质量感。
class PopIn extends StatefulWidget {
  final Widget child;
  final double fromScale;

  /// 覆盖默认弹簧（庆祝场景可传 [AppSprings.celebrate] 加强回弹）。
  final SpringDescription spring;

  const PopIn({
    super.key,
    required this.child,
    this.fromScale = 0.88,
    this.spring = AppSprings.state,
  });

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // unbounded：允许弹簧超调越过 1.0。用有界 controller 会把超调 clamp 掉，
    // 结果就是「没有回弹」——正是旧 easeOutBack 想模拟却模拟不像的东西。
    _controller = AnimationController.unbounded(vsync: this);
    _controller.animateWith(SpringSimulation(widget.spring, 0, 1, 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 减弱动态效果：呈现最终态（不重放）
    if (reducedMotionOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _controller.value; // 弹簧可短暂 >1 超调
        final scale = widget.fromScale + (1 - widget.fromScale) * v;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// 按压微交互：按下轻微缩小、松开弹簧回弹。
/// 自身持有手势回调（onTap/onLongPress），适合替换裸 GestureDetector。
///
/// 缩放全程由 [spring] 驱动，不再接受 `downDuration` / `upDuration`——
/// 贝塞尔曲线的固定时长表达不了「按下快、回弹带质量」的手感。
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double downScale;

  /// 覆盖默认弹簧（大卡片可传 [AppSprings.state] 让回弹更重）。
  final SpringDescription spring;

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.downScale = 0.96,
    this.spring = AppSprings.interaction,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 静止值 1.0（未按下）；unbounded 允许回弹超调越过 1.0。
    _controller = AnimationController.unbounded(vsync: this, value: 1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (widget.onTap == null) return;
    _controller.animateWith(
      SpringSimulation(
        widget.spring,
        _controller.value,
        pressed ? widget.downScale : 1.0,
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 减弱动态效果：仍要保留手势，只去掉缩放（见文件头注释的历史 bug）。
    if (reducedMotionOf(context)) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap != null ? (_) => _setPressed(true) : null,
      onTapUp: widget.onTap != null ? (_) => _setPressed(false) : null,
      onTapCancel: widget.onTap != null ? () => _setPressed(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) =>
            Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// 一次性小彩带爆发（成就庆祝）。
/// 用 CustomPainter 绘制，仅叠加在已有层之上（IgnorePointer），不阻塞交互。
class ConfettiBurst extends StatefulWidget {
  final int count;
  final double originDxFactor; // 横向中心偏移（0.5 = 居中）
  final double originDyFactor; // 纵向中心偏移（0.42 → 略偏上的爆发点）

  const ConfettiBurst({
    super.key,
    this.count = 26,
    this.originDxFactor = 0.5,
    this.originDyFactor = 0.42,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _particles =
        List.generate(widget.count, (_) => _ConfettiParticle(_random));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotionOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _controller.value,
            originDx: widget.originDxFactor,
            originDy: widget.originDyFactor,
          ),
        ),
      ),
    );
  }
}

class _ConfettiParticle {
  final double angle; // 发射方向（弧度）
  final double speed; // 初速度
  final double size;
  final double wobble; // 摆动频率
  final double rotationSpeed;
  final Color color;

  _ConfettiParticle(math.Random random)
      : angle = -math.pi * 0.5 + (random.nextDouble() - 0.5) * 2.0,
        speed = 240 + random.nextDouble() * 260,
        size = 6 + random.nextDouble() * 6,
        wobble = 6 + random.nextDouble() * 8,
        rotationSpeed = (random.nextDouble() - 0.5) * 12,
        color = _palette[random.nextInt(_palette.length)];

  // 庆祝场景正好是「撞色大块」唯一被允许全铺的时刻，直接取原色档（ADR-0044）。
  static const _palette = <Color>[
    AppBrutal.yellow,
    AppBrutal.cyan,
    AppBrutal.coral,
    AppBrutal.lime,
    AppBrutal.violet,
  ];
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress; // 0..1
  final double originDx;
  final double originDy;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
    required this.originDx,
    required this.originDy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final g = size.height / 700.0; // 粗略像素密度缩放
    final cx = size.width * originDx;
    final cy = size.height * originDy;

    // 前 70% 为扩散阶段，后 30% 逐渐淡出
    final fade = progress < 0.7 ? 1.0 : (1.0 - progress) / 0.3;

    for (final p in particles) {
      final past = progress * 1.1; // 归一化时长（秒）
      final px = cx + math.cos(p.angle) * p.speed * past * g +
          math.cos(past * p.wobble) * 18 * g;
      final py = cy + math.sin(p.angle) * p.speed * past * g +
          300 * past * past * g; // 重力下沉

      if (py > size.height || fade <= 0) continue;

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(past * p.rotationSpeed);
      // 高速时轻微拉伸，更自然
      final stretch = 1 + (p.speed * g * 0.004).clamp(0.0, 0.3);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: p.size * g * stretch,
        height: p.size * g / stretch,
      );
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}