import 'package:cupertino_ui/cupertino_ui.dart';

import '../theme/app_theme.dart';

/// 通用加载状态。
///
/// 当 [skeleton] 为 true 时，显示骨架屏（对应当前页面的内容形状）；
/// 否则显示居中的柔和 spinner + 可选文案。
class AppLoading extends StatelessWidget {
  final String? message;
  final bool skeleton;
  final int skeletonLines;

  const AppLoading({
    super.key,
    this.message,
  })  : skeleton = false,
        skeletonLines = 0;

  /// 骨架屏：模拟列表/卡片内容的形状
  const AppLoading.skeleton({
    super.key,
    this.skeletonLines = 6,
  })  : skeleton = true,
        message = null;

  @override
  Widget build(BuildContext context) {
    if (skeleton) return _SkeletonList(lines: skeletonLines);

    final app = AppTheme.colorsOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CupertinoActivityIndicator(
              color: app.primary,
              radius: 16,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              style: AppTheme.textOf(context).bodyLarge?.copyWith(
                    color: app.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  final int lines;
  const _SkeletonList({required this.lines});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: lines,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) {
        // 交错卡片高度，营造真实感
        final withCover = i % 3 == 0;
        return _SkeletonCard(withCover: withCover);
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final bool withCover;
  const _SkeletonCard({required this.withCover});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppTheme.colorsOf(context).surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppTheme.colorsOf(context).outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withCover) ...[
            const _ShimmerBox(width: 72, height: 72, radius: AppRadius.sm),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ShimmerBox(width: double.infinity, height: 18),
                const SizedBox(height: AppSpacing.sm),
                _ShimmerBox(
                  width: withCover ? double.infinity : 220,
                  height: 16,
                ),
                const SizedBox(height: AppSpacing.sm),
                const _ShimmerBox(width: 120, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = AppRadius.xs,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final base = app.surfaceContainerHighest;
    final highlight = app.surface;

    return SizedBox(
      width: widget.width == double.infinity ? null : widget.width,
      height: widget.height,
      child: LayoutBuilder(
        builder: (_, c) {
          final w = widget.width == double.infinity ? c.maxWidth : widget.width;
          return AnimatedBuilder(
            animation: _anim,
            builder: (_, __) {
              return Container(
                width: w,
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: _SlideGradient(_anim.value),
                    colors: [
                      base,
                      highlight,
                      base,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double value;
  const _SlideGradient(this.value);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * value, 0, 0);
  }
}
