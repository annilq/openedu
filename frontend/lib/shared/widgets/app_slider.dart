import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSlider, ShadSliderController;

import '../theme/app_theme.dart';

/// 设计系统滑块（ADR-0044 新粗野）。
///
/// 直接包裹 `ShadSlider` 并套用项目令牌，使滑块与全站控件同一套视觉语言：
/// - 激活轨道 = `accent`（品牌蓝），与 `ShadProgress` / `ShadSwitch` 选中态同色；
/// - 空轨道 = `surfaceActive`（沉色凹槽），不靠边框、靠色差表达（与进度类控件一致，
///   不在轨道外包墨黑描边——那会和作用域内的 `ShadProgress` 等脱节）；
/// - thumb = 纸面白底 + **墨黑 2px 描边**：这是修复重点。shadcn 默认 thumb 边框是
///   `primary` 蓝，与全站「2px 墨黑描边」母题冲突（卡片 / 按钮 / 勾选 / 开关的描边都是
///   墨黑 `outline`）。
/// - 禁用态走沉色 + 灰描边，不靠全局 `disabledOpacity`（ShadSlider 不消费它）。
///
/// **无受控组件**：当前值托管在 [ShadSliderController] 上。外部状态变化（重置 / 动画
/// 跟随）必须同步 `controller.value`，否则滑块卡在旧值。
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.controller,
    this.min,
    this.max,
    this.divisions,
    this.onChanged,
    this.enabled = true,
    this.label,
  });

  final ShadSliderController controller;
  final double? min;
  final double? max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final bool enabled;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colorsOf(context);
    return ShadSlider(
      controller: controller,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: enabled ? onChanged : null,
      enabled: enabled,
      label: label,
      // —— 新粗野令牌（ADR-0044）——
      activeTrackColor: c.accent,
      inactiveTrackColor: c.surfaceActive,
      thumbColor: c.surfaceRaised,
      thumbBorderColor: c.outline,
      disabledActiveTrackColor: c.accent.withValues(alpha: 0.45),
      disabledInactiveTrackColor: c.surfaceActive,
      disabledThumbColor: c.surfaceActive,
      disabledThumbBorderColor: c.onSurfaceVariant,
      trackHeight: 10,
      thumbRadius: 10,
    );
  }
}
