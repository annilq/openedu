import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/app_theme.dart';
import 'reflection_scene.dart';
import 'reflection_scene_data.dart';

/// 轴对称对折演示弹窗（ADR-0061 §V）：画廊里点一个图形 → 弹这个框。
///
/// 框里放的是**完整的** [ReflectionSceneWidget]——播放 / 暂停、拖对折进度、旋转与
/// 平移对称轴，以及实时「180° 时两侧能否重合」的判定，与页内单场景是同一个组件、
/// 同一套交互，不存在「弹窗里是张静态图」这种退化。
///
/// 为什么画布边长要按**屏高**夹一下：[ReflectionSceneWidget] 的画布是「边长 = 可用
/// 宽度」的正方形——弹窗给多宽它就多高。再叠加状态条 / 播放条 / 三个轴滑块（≈ 200px
/// 固定开销），不夹的话 1024×768 的横屏平板上弹窗会直接顶出屏幕（512 + 200 > 768）。
class ReflectionSceneDialog {
  ReflectionSceneDialog._();

  /// 画布边长上限 / 下限。
  ///
  /// 上限 420：再大就撑爆横屏平板；下限 220：小屏上顶点还得数得清，低于它
  /// 「等腰三角形 vs 等边三角形」在画布上已经分辨不出来。
  static const double maxCanvasSide = 420;

  static const double minCanvasSide = 220;

  /// 画布之外弹窗要吃掉的竖直开销：ShadDialog 内边距 + 标题 + 关闭按钮 + 状态条 /
  /// 播放条 / 三个轴滑块（场景自带的固定部分）+ 屏幕留白。
  static const double _chromeHeight = 320;

  /// 画布之外弹窗要吃掉的水平开销：ShadDialog 内边距 24×2 + 屏幕留白。
  static const double _chromeWidth = 64;

  static Future<void> show(
    BuildContext context, {
    required ReflectionSceneData data,
    String? optionLabel,
    /// 编辑器语境下把轴滑块变动写回父级（见 [ReflectionSceneWidget.onAxisChanged]）。
    /// 学生 / 普通预览不传，无副作用。仅当 [data.showAxisControls] 为 true（弹窗内
    /// 显示轴滑块）时这个回调才会被触发。
    void Function(double angle, double x, double y)? onAxisChanged,
  }) {
    final mq = MediaQuery.of(context);
    final byHeight = mq.size.height - _chromeHeight;
    final byWidth = mq.size.width - _chromeWidth;
    final side = math
        .min(math.min(maxCanvasSide, byHeight), byWidth)
        .clamp(minCanvasSide, maxCanvasSide);
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final name = data.figureLabel ?? '图形';
    final title =
        optionLabel == null ? '$name · 对折演示' : '$optionLabel $name · 对折演示';
    return showShadDialog<void>(
      context: context,
      barrierColor: app.scrim,
      builder: (ctx) => ShadDialog(
        // 关闭动作统一放在 actions（与 AppDialog 同口径），右上角那个默认 X 会与
        // 画布里的图形抢位置。
        closeIcon: const SizedBox.shrink(),
        constraints: BoxConstraints(maxWidth: side + _chromeWidth),
        title: Text(title, style: text.titleMedium?.copyWith(color: app.onSurface)),
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '关闭',
              style: text.labelMedium?.copyWith(color: app.onPrimary),
            ),
          ),
        ],
        // 钉宽 = 钉画布边长（场景画布是正方形），竖直方向由 ShadDialog 自带的
        // scrollable 兜住，任何屏高都不会 RenderFlex 溢出。
        child: SizedBox(
          width: side,
          child: ReflectionSceneWidget(
            data: data,
            onAxisChanged: onAxisChanged,
          ),
        ),
      ),
    );
  }
}
