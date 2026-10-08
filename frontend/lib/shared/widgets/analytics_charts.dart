import 'package:flutter/widgets.dart';

/// 学情图表适配器层（ADR-0075 §2.3）。
///
/// fl_chart 只作渲染引擎，**业务页严禁裸用** `BarChart` / `PieChart`——所有学情图表
/// 必须经由本文件的适配器，统一注入新粗野视觉令牌（`AppElevation.borderWidth` 直角描边 /
/// `AppColors.outline` 墨黑描边 / `AppBrutal` 撞色 / 无模糊硬阴影），并统一交互层
/// （`BarTouchData` / `PieTouchData` 的 tooltip / 高亮 / 钻取回调）。
///
/// 适配器落在 `shared/widgets/`：速览层（home 工作台）与分析层（analytics 迁移体）都
/// 要复用，而 `shared/` 是唯一允许被各 feature 引用的层（ADR-0037），避免 feature 间横切。
///
/// ⚠️ 本文件在 ticket 02 填充实现；当前为骨架占位，四个适配器均为空壳，仅供 01 建立
/// 文件与目录结构。落地前已过 `test/fl_chart_material_gate_test.dart`：本工程禁用
/// Material 控件、根树无 Material 祖先，fl_chart 内部不得引用任何 Material widget。
class AppDonutChart extends StatelessWidget {
  const AppDonutChart({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink(); // TODO(ticket 02)
}

/// 横向 / 竖向条形图适配器（薄弱知识点、掌握度）。
class AppBarChart extends StatelessWidget {
  const AppBarChart({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink(); // TODO(ticket 02)
}

/// 分组条形图适配器（正确率：练习 / 复习 / 总体）。
class AppGroupedBarChart extends StatelessWidget {
  const AppGroupedBarChart({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink(); // TODO(ticket 02)
}

/// 竖向堆叠条形图适配器（错题分布：活跃 / 已毕业）。
class AppStackedBarChart extends StatelessWidget {
  const AppStackedBarChart({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink(); // TODO(ticket 02)
}
