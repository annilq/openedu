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

/// 关闭某侧坐标轴标题（三侧共用的 const，避免重复构造）。
const SideTitles _noTitles = SideTitles(showTitles: false);

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
    // fl_chart 以 `centerSpaceRadius + section.radius` 作为**外圆**半径绘制（见
    // pie_chart_painter.dart 的 generateSectionPath / 全圆分支）。原实现令
    // section.radius = outer，外圆被放大到 ~1.62×outer、被 Stack 的 Clip.hardEdge
    // 裁掉左侧。修正：环厚 = outer - centerSpace - 描边宽，使外圆恰好落在 SizedBox
    // 边界内（再留半描边余量，杜绝抗锯齿溢出）。
    final centerSpace = outer * 0.62;
    final ringThickness = outer - centerSpace - AppElevation.borderWidthSm;
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
                      radius: ringThickness,
                      title: '',
                      borderSide: BorderSide(
                        color: scheme.outline,
                        width: AppElevation.borderWidthSm,
                      ),
                    ),
                  )
                  .toList(),
              centerSpaceRadius: centerSpace,
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

class _BarRow extends StatefulWidget {
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
  State<_BarRow> createState() => _BarRowState();
}

class _BarRowState extends State<_BarRow> {
  OverlayEntry? _tip;

  void _showTip() {
    if (_tip != null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      box.size.width,
      box.size.height,
    );
    final entry = OverlayEntry(
      builder: (_) => _LabelTip(
        rect: rect,
        label: widget.datum.label,
        scheme: widget.scheme,
        text: widget.text,
      ),
    );
    Overlay.of(context).insert(entry);
    _tip = entry;
  }

  void _hideTip() {
    _tip?.remove();
    _tip = null;
  }

  @override
  void dispose() {
    _hideTip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = widget.maxValue > 0
        ? (widget.datum.value / widget.maxValue).clamp(0.02, 1.0)
        : 0.0;
    final bar = Container(
      height: 18,
      decoration: BoxDecoration(
        color: widget.datum.color,
        border: Border.all(
          color: widget.scheme.outline,
          width: AppElevation.borderWidthSm,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          // 标签列按 flex 分配且向标签倾斜（flex:6 标签 / flex:5 条）：卡片越宽标签越宽，
          // 长知识点名放宽到 2 行而非 1 行截断；仍超长则长按整行弹出完整名（_LabelTip）。
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.datum.label,
                  style: widget.text.labelSmall
                      ?.copyWith(color: widget.scheme.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.datum.caption != null)
                  Text(
                    widget.datum.caption!,
                    style: widget.text.labelSmall
                        ?.copyWith(color: widget.scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 5,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct,
              child: bar,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _fmt(widget.datum.value, widget.unit),
            style: widget.text.labelMedium?.copyWith(
              color: widget.scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    final body = widget.onTap == null
        ? row
        // 可点区一律 AppFocusableAction（Material-free），承载键盘可达性 + 钻取。
        : AppFocusableAction(
            onTap: () => widget.onTap!(widget.index),
            semanticLabel: widget.datum.label,
            child: row,
          );
    // 长按整行弹出完整标签（叠在最上层 Overlay，不被卡片裁切）；独立于 AppFocusableAction
    // 的点击钻取，两者手势互不吞掉。
    return GestureDetector(
      onLongPress: _showTip,
      onLongPressEnd: (_) => _hideTip(),
      child: body,
    );
  }
}

/// 长按横条整行弹出的完整标签提示（非 Material，叠在最上层 Overlay，不被卡片裁切）。
class _LabelTip extends StatelessWidget {
  final Rect rect;
  final String label;
  final AppColors scheme;
  final AppText text;
  const _LabelTip({
    required this.rect,
    required this.label,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.bottom + 4,
      width: rect.width,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          border: Border.all(
            color: scheme.outline,
            width: AppElevation.borderWidthSm,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Text(
          label,
          style: text.labelSmall?.copyWith(color: scheme.onInverseSurface),
        ),
      ),
    );
  }
}

/// 分组条形图（正确率：练习 / 复习 / 总体）。fl_chart 纵向渲染 + 内置 tooltip。
///
/// [maxCategories] 超过则按总量取前 N-1 类目、余下并入「其他」桶，避免知识点维度下
/// 类目过多导致 x 轴标签互相遮挡（ADR-0075 工作台优化）；类目偏多时底部标签自动旋转。
class AppGroupedBarChart extends StatelessWidget {
  final List<GroupedBarDatum> data;
  final String? unit;
  final double height;
  final int maxCategories;

  const AppGroupedBarChart({
    super.key,
    required this.data,
    this.unit,
    this.height = 200,
    this.maxCategories = 6,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final capped = _capGrouped(data, maxCategories, scheme);
    final many = capped.length > 6;
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (int i = 0; i < capped.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  for (final s in capped[i].series)
                    BarChartRodData(
                      toY: s.value,
                      width: 14,
                      color: s.color,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
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
                reservedSize: many ? 64 : 32,
                getTitlesWidget: (v, m) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= capped.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: m,
                    angle: many ? -0.42 : 0.0,
                    // 强制标签留在 x 轴包围盒内：最左/最右标签不再溢出被容器裁掉。
                    fitInside: SideTitleFitInsideData.fromTitleMeta(m),
                    child: SizedBox(width: 72, child: Text(capped[idx].label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: _noTitles),
            rightTitles: const AxisTitles(sideTitles: _noTitles),
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

/// 分组条按系列总量降序截断，余下并入中性灰「其他」桶。
List<GroupedBarDatum> _capGrouped(
  List<GroupedBarDatum> data,
  int max,
  AppColors scheme,
) {
  if (data.length <= max) return data;
  final sorted = [...data]
    ..sort((a, b) => _groupTotal(b).compareTo(_groupTotal(a)));
  final top = sorted.take(max - 1).toList();
  double other = 0;
  for (final g in sorted.skip(max - 1)) {
    for (final s in g.series) {
      other += s.value;
    }
  }
  return [
    ...top,
    GroupedBarDatum(
      label: '其他',
      series: [
        BarSeries(name: '其他', value: other, color: scheme.onSurfaceVariant),
      ],
    ),
  ];
}

double _groupTotal(GroupedBarDatum g) =>
    g.series.fold(0.0, (s, e) => s + e.value);

/// 竖向堆叠条形图（错题分布：活跃 / 已毕业）。
///
/// [maxCategories] 超过则按总量取前 N-1 类目、余下活跃/已毕业分别求和并入「其他」桶，
/// 避免知识点维度下类目过多导致 x 轴标签互相遮挡（ADR-0075 工作台优化）；类目偏多时
/// 底部标签自动旋转。
class AppStackedBarChart extends StatelessWidget {
  final List<StackedBarDatum> data;
  final double height;
  final int maxCategories;

  const AppStackedBarChart({
    super.key,
    required this.data,
    this.height = 200,
    this.maxCategories = 6,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final capped = _capStacked(data, maxCategories, scheme);
    final many = capped.length > 6;
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (int i = 0; i < capped.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: capped[i].segments.fold<double>(
                      0,
                      (s, e) => s + e.value,
                    ),
                    width: 16,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    borderSide: BorderSide(
                      color: scheme.outline,
                      width: AppElevation.borderWidthSm,
                    ),
                    rodStackItems: _stackItems(
                      capped[i].segments,
                      scheme,
                    ),
                  ),
                ],
              ),
          ],
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: _noTitles),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: many ? 64 : 32,
                getTitlesWidget: (v, m) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= capped.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: m,
                    angle: many ? -0.42 : 0.0,
                    // 强制标签留在 x 轴包围盒内：最左/最右标签不再溢出被容器裁掉。
                    fitInside: SideTitleFitInsideData.fromTitleMeta(m),
                    child: SizedBox(width: 72, child: Text(capped[idx].label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: _noTitles),
            rightTitles: const AxisTitles(sideTitles: _noTitles),
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

/// 堆叠条按总量降序截断，余下活跃/已毕业分别求和并入「其他」桶。
List<StackedBarDatum> _capStacked(
  List<StackedBarDatum> data,
  int max,
  AppColors scheme,
) {
  if (data.length <= max) return data;
  final sorted = [...data]
    ..sort((a, b) => _stackTotal(b).compareTo(_stackTotal(a)));
  final top = sorted.take(max - 1).toList();
  double active = 0, graduated = 0;
  for (final g in sorted.skip(max - 1)) {
    for (final s in g.segments) {
      if (s.name == '活跃') {
        active += s.value;
      } else {
        graduated += s.value;
      }
    }
  }
  return [
    ...top,
    StackedBarDatum(
      label: '其他',
      segments: [
        StackedSegment(name: '活跃', value: active, color: scheme.semanticError),
        StackedSegment(
            name: '已毕业', value: graduated, color: scheme.semanticPositive),
      ],
    ),
  ];
}

double _stackTotal(StackedBarDatum g) =>
    g.segments.fold(0.0, (s, e) => s + e.value);

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
