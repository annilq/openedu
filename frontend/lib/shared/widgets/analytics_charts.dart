import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';

/// 学情图表适配器层（ADR-0075 §2.3）。
///
/// fl_chart 只作渲染引擎，**业务页严禁裸用** `BarChart` / `PieChart`——所有学情图表
/// 必须经由本文件的适配器，统一注入新粗野视觉令牌：直角小圆角（`AppRadius.xs`）、
/// 墨黑描边（`AppColors.outline` / `AppElevation.borderWidthSm`）、`AppBrutal` 撞色块、
/// 无模糊硬阴影（卡片自身承载阴影，图表元素不再画阴影）。交互层由 fl_chart 内置的
/// `BarTouchData` / `PieTouchData` 提供 tooltip / 高亮，横向条形则走 `AppFocusableAction`
/// 的点击钻取（键盘可达）。
///
/// 适配器落在 `shared/widgets/`（ADR-0037）：速览层（home 工作台）与分析层（analytics
/// 迁移体）都要复用，而 `shared/` 是唯一允许被各 feature 引用的层。数据以本文件的
/// 简单载体传入，**不 import 任何 feature 模型**，避免 shared → feature 反向依赖。
///
/// ⚠️ 单序列「横向条形」（`AppBarChart`）不绕 fl_chart——fl_chart 无原生横向模式、旋转
/// 方案会让轴标签失真；改用 token 完全可控的自定义横向条列表，同样只经适配器、业务页
/// 不裸用 fl_chart。环形 / 分组条 / 堆叠条仍由 fl_chart 承载（其纵向渲染 + tooltip 最稳）。
///
/// 落地前已过 `test/fl_chart_material_gate_test.dart`：本工程禁用 Material 控件、根树无
/// Material 祖先，fl_chart 内部不得引用任何 Material widget。

// =====================================================================
// §数据载体（shared 层不依赖 feature 模型）
// =====================================================================

/// 环形图扇区。
class DonutSegment {
  final double value;
  final Color color;
  final String? label;
  const DonutSegment({required this.value, required this.color, this.label});
}

/// 单序列条形（横向）：一个类目一条。
class BarDatum {
  final String label;
  final double value;
  final Color color;
  final String? caption;
  const BarDatum({
    required this.label,
    required this.value,
    required this.color,
    this.caption,
  });
}

/// 分组条形（纵向）的一组：一个类目下多条系列（如 练习 / 复习 / 总体）。
class GroupedBarDatum {
  final String label;
  final List<BarSeries> series;
  const GroupedBarDatum({required this.label, required this.series});
}

/// 分组条形的单条系列。
class BarSeries {
  final String name;
  final double value;
  final Color color;
  const BarSeries({required this.name, required this.value, required this.color});
}

/// 堆叠条形（纵向）的一组：一个类目下多段堆叠（如 活跃 / 已毕业）。
class StackedBarDatum {
  final String label;
  final List<StackedSegment> segments;
  const StackedBarDatum({required this.label, required this.segments});
}

/// 堆叠条形的单段。
class StackedSegment {
  final String name;
  final double value;
  final Color color;
  const StackedSegment({
    required this.name,
    required this.value,
    required this.color,
  });
}

/// 数值格式化：去小数，可带单位（如 `%`）。
String _fmt(double v, [String? unit]) =>
    '${v.round()}${unit ?? ''}';

/// 环形仪表（掌握度概览：已掌握 vs 剩余，中心 `X/Y`）。
class AppDonutChart extends StatelessWidget {
  final List<DonutSegment> segments;
  final String? centerTop;
  final String? centerBottom;
  final double size;

  /// 点击扇区回调（参数为扇区下标）；不传则禁用触摸。
  final void Function(int index)? onTap;

  const AppDonutChart({
    super.key,
    required this.segments,
    this.centerTop,
    this.centerBottom,
    this.size = 160,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final outer = size / 2;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sections: segments
                  .map(
                    (s) => PieChartSectionData(
                      value: s.value,
                      color: s.color,
                      radius: outer,
                      title: '',
                      borderSide: BorderSide(
                        color: scheme.outline,
                        width: AppElevation.borderWidthSm,
                      ),
                    ),
                  )
                  .toList(),
              centerSpaceRadius: outer * 0.62,
              sectionsSpace: AppElevation.borderWidthSm,
              borderData: FlBorderData(show: false),
              pieTouchData: PieTouchData(
                enabled: onTap != null,
                touchCallback: (event, response) {
                  if (onTap == null || event is! FlTapUpEvent) return;
                  final idx = response?.touchedSection?.touchedSectionIndex;
                  if (idx != null && idx >= 0 && idx < segments.length) {
                    onTap!(idx);
                  }
                },
              ),
            ),
          ),
          if (centerTop != null || centerBottom != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (centerTop != null)
                  Text(
                    centerTop!,
                    style: text.titleLarge
                        ?.copyWith(color: scheme.onSurface),
                  ),
                if (centerBottom != null)
                  Text(
                    centerBottom!,
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 横向条形列表（薄弱知识点 / 掌握度）。自定义渲染，token 完全可控、支持点击钻取。
class AppBarChart extends StatelessWidget {
  final List<BarDatum> data;
  final void Function(int index)? onTap;
  final String? unit;

  const AppBarChart({
    super.key,
    required this.data,
    this.onTap,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final maxV = data.fold<double>(0, (m, d) => math.max(m, d.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < data.length; i++)
          _BarRow(
            datum: data[i],
            maxValue: maxV,
            index: i,
            onTap: onTap,
            scheme: scheme,
            text: text,
            unit: unit,
          ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  final BarDatum datum;
  final double maxValue;
  final int index;
  final void Function(int index)? onTap;
  final AppColors scheme;
  final AppText text;
  final String? unit;

  const _BarRow({
    required this.datum,
    required this.maxValue,
    required this.index,
    required this.onTap,
    required this.scheme,
    required this.text,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final pct = maxValue > 0 ? (datum.value / maxValue).clamp(0.02, 1.0) : 0.0;
    final bar = Container(
      height: 18,
      decoration: BoxDecoration(
        color: datum.color,
        border: Border.all(
          color: scheme.outline,
          width: AppElevation.borderWidthSm,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  datum.label,
                  style: text.labelSmall?.copyWith(color: scheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (datum.caption != null)
                  Text(
                    datum.caption!,
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct,
              child: bar,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _fmt(datum.value, unit),
            style: text.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    // 可点区一律 AppFocusableAction（Material-free），承载键盘可达性 + 钻取。
    return AppFocusableAction(
      onTap: () => onTap!(index),
      semanticLabel: datum.label,
      child: row,
    );
  }
}

/// 分组条形图（正确率：练习 / 复习 / 总体）。fl_chart 纵向渲染 + 内置 tooltip。
class AppGroupedBarChart extends StatelessWidget {
  final List<GroupedBarDatum> data;
  final String? unit;
  final double height;

  const AppGroupedBarChart({
    super.key,
    required this.data,
    this.unit,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (int i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  for (final s in data[i].series)
                    BarChartRodData(
                      toY: s.value,
                      width: 14,
                      color: s.color,
                      borderRadius:
                          BorderRadius.circular(AppRadius.xs),
                      borderSide: BorderSide(
                        color: scheme.outline,
                        width: AppElevation.borderWidthSm,
                      ),
                    ),
                ],
              ),
          ],
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, m) => Text(
                  _fmt(v, unit),
                  style: text.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, m) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= data.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    data[idx].label,
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: _tooltip(scheme, text),
          ),
        ),
      ),
    );
  }
}

/// 竖向堆叠条形图（错题分布：活跃 / 已毕业）。
class AppStackedBarChart extends StatelessWidget {
  final List<StackedBarDatum> data;
  final double height;

  const AppStackedBarChart({
    super.key,
    required this.data,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (int i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].segments.fold<double>(
                      0,
                      (s, e) => s + e.value,
                    ),
                    width: 16,
                    borderRadius:
                        BorderRadius.circular(AppRadius.xs),
                    borderSide: BorderSide(
                      color: scheme.outline,
                      width: AppElevation.borderWidthSm,
                    ),
                    rodStackItems: _stackItems(
                      data[i].segments,
                      scheme,
                    ),
                  ),
                ],
              ),
          ],
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, m) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= data.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    data[idx].label,
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: _tooltip(scheme, text),
          ),
        ),
      ),
    );
  }
}

List<BarChartRodStackItem> _stackItems(
  List<StackedSegment> segments,
  AppColors scheme,
) {
  double from = 0;
  final items = <BarChartRodStackItem>[];
  for (final s in segments) {
    final to = from + s.value;
    items.add(
      BarChartRodStackItem(
        from,
        to,
        s.color,
        BorderSide(
          color: scheme.outline,
          width: AppElevation.borderWidthSm,
        ),
      ),
    );
    from = to;
  }
  return items;
}

/// 统一 tooltip 样式：墨黑底 + 纸色字 + 墨黑描边（新粗野反色，无模糊阴影）。
BarTouchTooltipData _tooltip(AppColors scheme, AppText text) =>
    BarTouchTooltipData(
      getTooltipColor: (BarChartGroupData g) => scheme.inverseSurface,
      tooltipBorder: BorderSide(
        color: scheme.outline,
        width: AppElevation.borderWidthSm,
      ),
      getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
        _fmt(rod.toY),
        (text.labelSmall ?? const TextStyle())
            .copyWith(color: scheme.onInverseSurface),
      ),
    );
