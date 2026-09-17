import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_motion.dart';

/// 通用空态占位：语义色块 + 标题 + 说明 + 可选主行动（+ 可选流程步骤）。
///
/// 与 [AppError] 是**同一套骨架**——88 色块 / 标题 / 说明 / 行动，差别只在语义：
/// 错误态给「重试」，空态给「下一步做什么」。共用骨架的理由是「加载 / 错误 / 空」
/// 三态会互相切换，骨架一致时切换不跳版式；各写一套就会出现「错误态居中 88 块、
/// 空态贴左上 40 图标」的错层。
///
/// 设计约束：
/// - **空态不是「没有内容」，而是「还没到那一步」**。它必须回答两个问题：
///   **为什么是空的**（[message]）与**下一步做什么**（[actionLabel] / [steps]）。
///   只写一句「暂无数据」的空态是死胡同——用户知道没有，但不知道该点哪。
/// - 宽度收口 [AppLayout.contentEmpty]（440）：大屏下说明文字不会拉成长行。
/// - 密集区域（卡片内、概览小栏）用 [AppEmptyState.inline]：88 大色块在那里
///   会抢走内容区的重量，横向 48 小色块 + 两行字才是对的重量级。
/// - 色块是否投影由 [tone] 决定：安静态是**占位**（不投影，它是背景的一部分），
///   强调态是**物体**（投影，需要从纸底上「拿出来」）。
class AppEmptyState extends StatelessWidget {
  final IconData icon;

  /// 一句话结论（「草稿箱是空的」），不要写成「暂无数据」。
  final String title;

  /// 为什么是空的 / 下一步会发生什么。
  final String message;

  /// 主行动文案；与 [onAction] 成对出现，缺一个就不渲染按钮。
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  /// 可选的「流程说明」步骤（如 布置 → 复核派发 → 娃娃完成）。
  ///
  /// 只在该空态是**首次空**（用户还没跑通过流程）时给；跑通过之后再看就是噪音。
  final List<String>? steps;

  /// 色块底：`null` = 安静态（`surfaceContainerLow` + 墨黑边 + onSurfaceVariant 图标）；
  /// 传 [AppBrutal] 撞色 = 强调态（撞色底 + 墨黑边 + [AppBrutal.onColor] 图标），
  /// 用于娃娃端这类需要情绪价值的场景。
  final Color? tone;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.steps,
    this.tone,
  }) : _inline = false;

  /// 紧凑内联变体：横向 48 色块 + 标题 + 说明（+ 可选行动）。
  ///
  /// 用于**卡片内 / 概览小栏**这类不该出现 88 大色块的位置。左对齐（跟随内容
  /// 列的左缘），不居中——它在内容流里，不是一个独立的屏。
  const AppEmptyState.inline({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.steps,
    this.tone,
  }) : _inline = true;

  final bool _inline;

  /// 色块边长：完整版 88（与 [AppError] 同），内联版 48。
  double get _blockSize => _inline ? 48 : 88;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final emphasized = tone != null;

    final blockFill = emphasized ? tone! : app.surfaceContainerLow;
    final blockIconColor =
        emphasized ? AppBrutal.onColor(tone!) : app.onSurfaceVariant;
    final blockShadows = emphasized && app.brightness != Brightness.dark
        ? AppElevation.hard(app.outline)
        : AppElevation.none;

    final block = Container(
      width: _blockSize,
      height: _blockSize,
      decoration: BoxDecoration(
        color: blockFill,
        // 装饰性大圆角（28 / 32）不在 [AppRadius] 的控件档位内，按场景取；
        // 内联版缩到 48 后沿用卡片圆角，否则小方块配大圆角会显得「软」。
        borderRadius: BorderRadius.circular(_inline ? AppRadius.card : 28),
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidth,
        ),
        boxShadow: blockShadows,
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: _inline ? 24 : 44,
        color: blockIconColor,
      ),
    );

    final heading = Text(
      title,
      textAlign: _inline ? TextAlign.start : TextAlign.center,
      style: (_inline ? text.bodyMedium : text.titleLarge)?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );

    final body = Text(
      message,
      textAlign: _inline ? TextAlign.start : TextAlign.center,
      style: (_inline ? text.labelSmall : text.bodyLarge)?.copyWith(
        color: app.onSurfaceVariant,
        height: 1.5,
      ),
    );

    final action = _buildAction(context, app, text);
    final stepsWidget = steps == null ? null : _buildSteps(context, app, text);

    final content = _inline
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              block,
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: AppSpacing.xs2),
                    body,
                    if (stepsWidget != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      stepsWidget,
                    ],
                    if (action != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      action,
                    ],
                  ],
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              block,
              const SizedBox(height: AppSpacing.lg),
              heading,
              const SizedBox(height: AppSpacing.sm),
              body,
              if (stepsWidget != null) ...[
                const SizedBox(height: AppSpacing.xl),
                stepsWidget,
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpacing.xl),
                action,
              ],
            ],
          );

    // PopIn 内部已按 reduce-motion 降级（app_motion.dart），这里不用再判一次。
    final animated = PopIn(child: content);

    if (_inline) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.contentEmpty),
        child: animated,
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentEmpty),
          child: animated,
        ),
      ),
    );
  }

  Widget? _buildAction(BuildContext context, AppColors app, AppText text) {
    if (actionLabel == null || onAction == null) return null;
    // 空态里唯一的出口 → 主行动档，不硬编码像素。
    return Wrap(
      alignment: _inline ? WrapAlignment.start : WrapAlignment.center,
      children: [
        ShadButton(
          size: ShadButtonSize.lg,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          onPressed: onAction,
          leading: actionIcon == null
              ? null
              : Icon(actionIcon, size: 18, color: app.onPrimary),
          child: Text(
            actionLabel!,
            style: text.labelMedium?.copyWith(color: app.onPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildSteps(BuildContext context, AppColors app, AppText text) {
    final items = steps!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          _inline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(
                bottom: i == items.length - 1 ? 0 : AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _StepBadge(index: i + 1, app: app, text: text),
                const SizedBox(width: AppSpacing.sm),
                // 步骤文字是「说明」不是「标题」：宽度给了 contentEmpty，
                // 用 Flexible 兜住极端窄屏（内联版落在窄卡片里）。
                Flexible(
                  child: Text(
                    items[i],
                    style: text.bodySmall?.copyWith(
                      color: app.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 步骤序号徽标：1.5px 描边小方块（[AppElevation.borderWidthSm] 的密集小色块档）。
class _StepBadge extends StatelessWidget {
  final int index;
  final AppColors app;
  final AppText text;
  const _StepBadge({required this.index, required this.app, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: app.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidthSm,
        ),
      ),
      child: Text(
        '$index',
        style: text.labelSmall?.copyWith(
          color: app.onSurface,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
