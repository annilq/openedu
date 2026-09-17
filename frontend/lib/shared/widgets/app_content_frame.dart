import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 内容宽度上限框（ADR-0045）的唯一出口。
///
/// 此前全仓有 14 处手抄同一段 `Align` + `ConstrainedBox(maxWidth: contentWide)`，
/// 各自写、各自微调：`AdaptiveShell` 用 `topCenter`，而塞进壳里的那些页面写的却是
/// `topLeft`。手抄的代价不是重复本身，而是**改宽度或改对齐时要记得改 14 处**，
/// 漏一处就是某张页面独自变宽。
///
/// 本组件刻意只做一件事：**钉宽度上限 + 定横向/竖向对齐**。它不负责背景、
/// 不负责导航、不负责返回——那些是调用方或 [AppPushedPage] 的事。
///
/// 为什么是 [Align] 而不是 [Center]：
/// `Center` 竖向也居中，壳内的内容区一旦不足一屏会浮到屏幕中间；
/// `Align` 只约束传进来的那个方向，竖向保持贴顶（ADR-0045 既定口径）。
class AppContentFrame extends StatelessWidget {
  const AppContentFrame({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.contentWide,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;

  /// 宽度上限，默认取 [AppLayout.contentWide]（1080）。
  ///
  /// 需要更窄的页面（登录 480 / 答题 820）传更紧的值即可——内层更紧者生效。
  final double maxWidth;

  /// 横向/竖向对齐。**沿用各处原本的取值**：塞进壳里的那些是 `topLeft`，
  /// 独立整页才是 `topCenter`。迁移时照抄，不要顺手「统一」。
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
