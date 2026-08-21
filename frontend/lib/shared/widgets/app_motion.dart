import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';

/// 轻量运动组件，服务于「轻快愉悦」的情绪目标（见 .impeccable.md）。
///
/// 约定：
/// - 一律只动 `transform + opacity`（GPU 合成），不触发布局/绘制重排。
/// - 时长 200-300ms，入场 300ms、按压反馈 120→260ms。
/// - 尊重系统减弱动画设置：`MediaQuery.disableAnimationsOf == true` 时退化为静态。
/// - 归还弹跳统一用 `easeOutBack`（轻微超调 = 亲切的弹簧感，不夸张）。

/// 判断系统是否「减弱动态效果」。
bool reducedMotionOf(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// 弹簧入场：缩放 + 淡入，一次执行（initState 触发，不随重建重放）。
/// 用于成就图标、结果卡片、首页 Banner 等「登场」时刻。
class PopIn extends StatefulWidget {
  final Widget child;
  final double fromScale;
  final Duration duration;

  const PopIn({
    super.key,
    required this.child,
    this.fromScale = 0.88,
    this.duration = const Duration(milliseconds: 320),
  });

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    // easeOutBack：轻微超调后回弹，营造亲切弹簧感
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 减弱动态效果：呈现最终态（不重放）
    if (reducedMotionOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value; // 0..1（easeOutBack 可短暂 >1 超调）
        final scale = widget.fromScale + (1 - widget.fromScale) * t;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// 按压微交互：按下轻微缩小、松开弹簧回弹。
/// 自身持有手势回调（onTap/onLongPress），适合替换裸 GestureDetector。
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double downScale;
  final Duration downDuration;
  final Duration upDuration;

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.downScale = 0.96,
    this.downDuration = const Duration(milliseconds: 120),
    this.upDuration = const Duration(milliseconds: 280),
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  bool get _reduce => reducedMotionOf(context);

  @override
  Widget build(BuildContext context) {
    if (_reduce) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp:
          widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel:
          widget.onTap != null ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.downScale : 1.0,
        duration: _pressed ? widget.downDuration : widget.upDuration,
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
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

  static const _palette = <Color>[
    Color(0xFF43A047), // 植物绿
    Color(0xFFF97316), // 暖橙
    Color(0xFF38BDF8), // 天蓝
    Color(0xFFFB923C), // 暖橙淡
    Color(0xFF6FD0F4), // 天蓝淡
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