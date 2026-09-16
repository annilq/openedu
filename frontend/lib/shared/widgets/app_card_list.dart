import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 长列表的条目区：**宽度够时自动排成两列**（ADR-0053）。
///
/// 只解决「一堆卡片怎么排」，取数在 `shared/presentation/paging.dart`，列表项的
/// 内容截断在各页面自己——这里唯一关心的是列数与间距。
///
/// 三个长列表（题库 / 任务 / 错题本）此前行距、页边距各不相同，切换页面时有
/// 「这个页面更挤」的突兀感；列数判定也只是「宽度够就两列」一件事，各页面各写
/// 一遍必然在阈值上分叉。所以收口成两个组件：
/// - [AppCardSliver]：给 `CustomScrollView` 用，懒加载（列表可能上百条）。
/// - [AppCardList]：给普通 `Column` 用（列表区嵌在卡片里、外层另有滚动容器）。
///
/// **不用 `SliverGrid`**：它的行高由 `childAspectRatio` 钉死，而卡片高度随题干
/// 行数、解析是否展开变化，钉死行高会直接裁掉内容。改成分行 Row，行高由最高的
/// 那张卡自然决定。
class AppCardSliver extends StatelessWidget {
  const AppCardSliver({
    super.key,
    required this.width,
    required this.itemCount,
    required this.itemBuilder,
  });

  /// 列表区的可用宽度（`LayoutBuilder` 的 `constraints.maxWidth`，未减页边距）。
  ///
  /// 组件自己减 [AppLayout.listGutter]，页面不必再各算一遍「宽度减 32」。
  final double width;

  final int itemCount;

  /// 第 [index] 张卡；无需自带行距，间距由本组件统一给。
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final columns = AppLayout.listColumnsFor(width - 2 * AppLayout.listGutter);
    return SliverList.builder(
      itemCount: _rowCount(itemCount, columns),
      itemBuilder: (context, row) => Padding(
        padding: const EdgeInsets.only(bottom: AppLayout.listRowGap),
        child: _CardRow(
          columns: columns,
          row: row,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}

/// 非懒加载版：列表区嵌在卡片里、外层已有滚动容器时用（如题库）。
///
/// 与 [AppCardSliver] 只有「是不是 sliver」的差别，列数与间距共用同一套令牌。
class AppCardList extends StatelessWidget {
  const AppCardList({
    super.key,
    required this.width,
    required this.itemCount,
    required this.itemBuilder,
  });

  /// 可用内容宽度（已减去所在容器的内边距）。
  final double width;

  final int itemCount;

  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final columns = AppLayout.listColumnsFor(width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < _rowCount(itemCount, columns); row++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppLayout.listRowGap),
            child: _CardRow(
              columns: columns,
              row: row,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
          ),
      ],
    );
  }
}

int _rowCount(int itemCount, int columns) => (itemCount / columns).ceil();

/// 一行 [columns] 张卡；末行不满时用 `Expanded + SizedBox` 占位，
/// 保持列宽与整行一致（否则末行只有一张卡时它会被拉满整行）。
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.columns,
    required this.row,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int columns;
  final int row;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var c = 0; c < columns; c++) {
      if (c > 0) children.add(const SizedBox(width: AppLayout.listColumnGap));
      final index = row * columns + c;
      // 顶部对齐而非拉伸：拉伸会让矮卡跟着同列最高的卡变高，留白反而更多。
      children.add(
        Expanded(
          child: index < itemCount
              ? itemBuilder(context, index)
              : const SizedBox.shrink(),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
