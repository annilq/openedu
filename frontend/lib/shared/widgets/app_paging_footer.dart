import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_loading.dart';

/// 分页列表底部：加载中 / 加载失败重试 / 加载更多 / 已全部加载（ADR-0053）。
///
/// 三个长列表（题库 / 任务 / 错题本）底部必须是同一套语言，否则「这个列表还有没有
/// 下一页」就要靠用户猜。四条分支：
///
/// - **加载中**：只换底部这一行，不整页闪一下（首屏加载才用整页骨架）。
/// - **加载失败**：**保留已加载的数据**，只在这里给原因 + 「重试」。追加失败就把整
///   个列表清空是最糟的处理——用户已经滑到这里了。
/// - **还有下一页**：显式「加载更多」按钮 + 「还有 N 条」。按钮不是装饰：触底自动
///   加载对键盘 / 读屏用户不可达，且是触底判定失败时的兜底。
/// - **已到底**：发丝线 + 文案，给长列表一个明确的终点。
class AppPagingFooter extends StatelessWidget {
  const AppPagingFooter({
    super.key,
    required this.hasMore,
    required this.onLoadMore,
    this.isLoadingMore = false,
    this.moreError,
    this.remaining = 0,
  });

  /// 还有下一页（由游标决定，不是由 total 决定）。
  final bool hasMore;

  /// 正在追加下一页。
  final bool isLoadingMore;

  /// 追加失败的原因；null = 无失败。
  final String? moreError;

  /// 还没加载的条数（total - loaded），只用于「还有 N 条」展示。
  final int remaining;

  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: AppLoading(message: '加载中…'),
      );
    }
    if (moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            Text(
              '加载失败：$moreError',
              style: AppTheme.textOf(context).labelSmall?.copyWith(
                    color: app.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onLoadMore,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            if (remaining > 0)
              Text(
                '还有 $remaining 条',
                style: AppTheme.textOf(context).labelSmall?.copyWith(
                      color: app.onSurfaceVariant,
                    ),
              ),
            if (remaining > 0) const SizedBox(height: AppSpacing.sm),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onLoadMore,
              child: const Text('加载更多'),
            ),
          ],
        ),
      );
    }
    // 已到底：发丝线 + 文案。没有它，用户会一直往下滑等更多内容。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: _hairline(app)),
          const SizedBox(width: AppSpacing.md),
          Text(
            '已全部加载',
            style: AppTheme.textOf(context).labelSmall?.copyWith(
                  color: app.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _hairline(app)),
        ],
      ),
    );
  }

  Widget _hairline(AppColors app) => Container(
        height: AppElevation.borderWidthHairline,
        color: app.outline,
      );
}
