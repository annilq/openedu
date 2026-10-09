import 'package:flutter/widgets.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';

/// 响应式栅格（ADR-0075 工作台优化）：宽屏多列、窄屏单列。
///
/// 单屏 landing 下，速览层 4 卡 / 分析层 2 图需在宽屏并排以压缩纵向高度，
/// 窄屏退回单列堆叠。列宽按可用宽度均分并扣除间距，卡片宽度自此被约束、
/// fl_chart 图表不会因无限宽而放大或让 x 轴标签互相遮挡。
class AppResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int colsWide;
  final double breakpoint;
  final double spacing;

  const AppResponsiveGrid({
    super.key,
    required this.children,
    this.colsWide = 2,
    this.breakpoint = 820,
    this.spacing = AppSpacing.md,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final cols = c.maxWidth >= breakpoint ? colsWide : 1;
        if (cols == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        final cellW = (c.maxWidth - spacing * (cols - 1)) / cols;
        final rows = <Widget>[];
        for (int i = 0; i < children.length; i += cols) {
          final cells = <Widget>[];
          for (int j = 0; j < cols && i + j < children.length; j++) {
            cells.add(SizedBox(width: cellW, child: children[i + j]));
          }
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: rows.isEmpty ? 0 : spacing),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int j = 0; j < cells.length; j++) ...[
                    if (j > 0) SizedBox(width: spacing),
                    cells[j],
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}
