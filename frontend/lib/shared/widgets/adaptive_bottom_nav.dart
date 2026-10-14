import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'nav_section.dart' show AdaptiveNavDestination;
import 'app_focusable_action.dart';

/// 学生端紧凑档底部导航（ADR-0045 紧凑档的学生侧形态）。
///
/// 从 [AdaptiveShell] 抽出：底栏是紧凑档学生端唯一的导航形态，它的窄屏降级
/// （[AppLayout.bottomNavNarrowMax] 以下不再等分）与侧栏 / 抽屉无关，塞在壳里
/// 只会让壳继续变长。
///
/// 分档**只**依据可用宽度（[LayoutBuilder] 的 `constraints.maxWidth`），不认设备
/// 形态与屏幕朝向（ADR-0045）：
///
/// | 可用宽度 | 排布 |
/// |---|---|
/// | ≥ [AppLayout.bottomNavNarrowMax] | 等分（历史排布，逐像素不动） |
/// | `items.length × [AppLayout.tapTarget]` ≤ 宽度 < 阈值 | 自然分布 + 每项至少 [AppLayout.tapTarget] 宽 |
/// | < 上述下限 | 只留图标 |
///
/// 最后一档是物理兜底：五个 [AppLayout.tapTarget] 宽的命中区本身就占 220，窄于
/// 此值无论如何都放不下，此时宁可隐藏标签——标签被压成省略号比没有标签更糟
/// （读不出内容，还多了个「这里被截断了」的视觉噪声），而 [AppFocusableAction]
/// 的 `semanticLabel` 仍带着完整名称，读屏不受影响。
class AdaptiveBottomNav extends StatelessWidget {
  /// 页签 + 「我的」，由调用方按唯一导航状态装配（ADR-0059）。
  final List<AdaptiveNavDestination> items;

  const AdaptiveBottomNav({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceSunken,
        border: Border(
          top: BorderSide(
            color: scheme.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppLayout.bottomNavHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final iconOnly = width < items.length * AppLayout.tapTarget;
              final natural = !iconOnly && width < AppLayout.bottomNavNarrowMax;
              return Row(
                // 等分档下所有子项都是 Expanded、自由空间为 0，对齐方式不起作用，
                // 因此这里可以无条件写 spaceAround：它只影响自然分布档的留白。
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final d in items)
                    if (natural)
                      // 自然分布：按内容收宽（不再被等分硬撑），但命中区不得小于
                      // tapTarget——可点区域的大小不能让位给「看起来均匀」。
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minWidth: AppLayout.tapTarget),
                          child: _BottomNavItem(destination: d),
                        ),
                      )
                    else
                      Expanded(
                        child: _BottomNavItem(
                            destination: d, showLabel: !iconOnly),
                      ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 底栏单项：图标 + 一行标签（[showLabel] 为 false 时只留图标）。
///
/// 选中态语言（accent 图标 + w600 文字）与历史一致，不随档位变化——档位只改
/// 横向分布，不改语义。
class _BottomNavItem extends StatelessWidget {
  final AdaptiveNavDestination destination;
  final bool showLabel;

  const _BottomNavItem({required this.destination, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final color = destination.active ? scheme.accent : scheme.onSurfaceVariant;
    return AppFocusableAction(
      onTap: destination.onTap,
      semanticLabel: destination.label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(destination.icon,
              size: AppLayout.bottomNavIconSize, color: color),
          if (showLabel) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              destination.label,
              style: AppTheme.textOf(context).labelSmall?.copyWith(
                    color: color,
                    fontWeight:
                        destination.active ? FontWeight.w600 : FontWeight.w500,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
