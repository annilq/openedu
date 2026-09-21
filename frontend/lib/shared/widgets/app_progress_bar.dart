import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 线性进度条：靛蓝填充。
class AppProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final target = value.clamp(0.0, 1.0);
    // 值变化 =「状态切换」，补一档隐式过渡。直接换 `ShadProgress.value` 会让条子
    // 硬跳：它的 determinate 实现是裸 `FractionallySizedBox`（零内部动画），
    // 「答完题看着掌握度条长出来」这个时刻的**进步信号本身就丢了**。
    //
    // begin == end：**首帧直接落在终值**，不扫一遍。掌握度表里每行都从 0 长出来
    // 会变成满屏噪声，何况列表滚动/回收会不断重放。只有挂载**之后**的值变化才过渡。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: target, end: target),
      // ⚠️ 隐式动画不自动尊重系统设置（见 [reducedMotionOf]）。
      duration: reducedMotionOf(context) ? Duration.zero : AppMotion.state,
      curve: AppCurves.state,
      builder: (context, animated, _) => ShadProgress(
        value: animated,
        minHeight: height,
        color: color ?? app.accent,
        backgroundColor: trackColor ?? app.surfaceContainerHighest,
      ),
    );
  }
}

// =====================================================================
// §语义化组件
// =====================================================================

/// Hover 感知的语义 pill：常态与 hover 态同步切换底色（克制版——同色微深，
/// 不填实饱和色），前景色保持不变，文字始终可读且整体协调。
///
/// 设计背景：shadcn 的 [ShadBadge] 仅支持单一 [foregroundColor]，hover 时
/// 背景切到 [hoverBackgroundColor] 而文字颜色不变；本 App 的 badge 主题未设
/// [hoverBackgroundColor]，导致 hover 背景变透明、文字残留容器前景色而不可读。
/// 这里自管 hover 状态，同时切换底色（同色微深）+ 保持前景，彻底解决「背景变、
/// 字不变、看不清」，且 hover 不再填实饱和色（修复标签成全站最吵元素的问题）。
