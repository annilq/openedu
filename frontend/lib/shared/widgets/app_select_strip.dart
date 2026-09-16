import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 列表顶部「多选」操作条（从 assistant 的 `_ManageStrip` 抽出）。
///
/// 多选入口与全选放在这里而非顶栏，因为 [AppTopBar] 的 trailing 槽位只有 40px、
/// 只够放一个图标动作（ADR-0045/0046），而这里是一整条可用宽度，能并排。
///
/// **状态切换**：
/// - 非勾选态：右侧一个「多选」按钮，调用 [onEnterSelecting]；
/// - 勾选态：左「已选 N 项」、右「全选 / 取消全选」按钮，调用 [onToggleSelectAll]，
///   行为由调用方按「已选 == 全部」决定全清还是全选；0 选且传了 [hintText] 时，
///   左侧显示 [hintText] 作为引导语（替代「已选 0 项」）。
///
/// 文案与几何遵循 ADR-0044/0046：文字走 `labelMedium`、主操作取 `primary`、
/// 计数取 `onSurface`；行内选中态已用 `surfaceActive` 底色 + 勾选标记，这里不再
/// 叠描边 / 图标，避免与列表行的选中语言撞风格。
class AppSelectStrip extends StatelessWidget {
  const AppSelectStrip({
    super.key,
    required this.selecting,
    required this.selectedCount,
    required this.totalCount,
    required this.onEnterSelecting,
    required this.onToggleSelectAll,
    this.hintText, // 0 选时显示引导语
  });

  final bool selecting;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onEnterSelecting;
  final VoidCallback onToggleSelectAll;

  /// 0 选时显示的引导语；缺省回退到「已选 0 项」。
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          if (selecting) ...[
            Text(
              selectedCount > 0
                  ? '已选 $selectedCount 项'
                  : (hintText ?? '已选 0 项'),
              style: text.labelMedium?.copyWith(color: scheme.onSurface),
            ),
            const Spacer(),
            TextButton(
              onPressed: onToggleSelectAll,
              child: Text(
                selectedCount == totalCount && totalCount > 0
                    ? '取消全选'
                    : '全选',
                style: text.labelMedium?.copyWith(color: scheme.primary),
              ),
            ),
          ] else ...[
            const Spacer(),
            TextButton(
              onPressed: onEnterSelecting,
              child: Text(
                '多选',
                style: text.labelMedium?.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
