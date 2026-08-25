import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// 加载状态展示模式。
enum _LoadingMode { spinner, skeleton, skeletonInline }

/// 通用加载状态。
///
/// - [AppLoading()]：居中柔和 spinner + 可选文案（整页/区域占位）。
/// - [AppLoading.skeleton]：整页骨架屏（可滚动 ListView，需有垂直边界）。
/// - [AppLoading.skeletonInline]：内联骨架行（Column，用于已滚动容器内的占位）。
class AppLoading extends StatelessWidget {
  final String? message;
  final int skeletonLines;
  final _LoadingMode _mode;

  const AppLoading({
    super.key,
    this.message,
  })  : _mode = _LoadingMode.spinner,
        skeletonLines = 0;

  /// 整页骨架屏：模拟列表/卡片内容的形状（可滚动）。
  const AppLoading.skeleton({
    super.key,
    this.skeletonLines = 6,
  })  : _mode = _LoadingMode.skeleton,
        message = null;

  /// 内联骨架行：Column 排布，用于已存在于滚动容器内的占位（不嵌套滚动）。
  const AppLoading.skeletonInline({
    super.key,
    this.skeletonLines = 3,
  })  : _mode = _LoadingMode.skeletonInline,
        message = null;

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _LoadingMode.skeleton:
        return _SkeletonList(lines: skeletonLines);
      case _LoadingMode.skeletonInline:
        return _SkeletonRows(lines: skeletonLines);
      case _LoadingMode.spinner:
        final app = AppTheme.colorsOf(context);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.loaderCircle,
                size: 36,
                color: app.primary,
              ).animate(onPlay: (c) => c.repeat()).rotate(
                    begin: 0,
                    end: 1,
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.linear,
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
}

/// 整页骨架：可滚动列表。
class _SkeletonList extends StatelessWidget {
  final int lines;
  const _SkeletonList({required this.lines});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: lines,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _SkeletonCard(withCover: i % 3 == 0),
      ),
    );
  }
}

/// 内联骨架：Column 排布，用于已存在于滚动容器内的占位。
class _SkeletonRows extends StatelessWidget {
  final int lines;
  const _SkeletonRows({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.md,
      ),
      child: Column(
        children: List.generate(
          lines,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _SkeletonCard(withCover: i % 3 == 0),
          ),
        ),
      ),
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
        color: AppTheme.colorsOf(context).surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
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

/// 骨架块（自研 shimmer 渐变，不依赖 Material/Cupertino）。
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
    final base = app.surfaceSunken;
    final highlight = app.surfaceRaised;

    return LayoutBuilder(
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
