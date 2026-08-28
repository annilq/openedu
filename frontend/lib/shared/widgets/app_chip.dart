import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// Material-free 选择 chip —— 用来替代 Material 的 [ChoiceChip] / [FilterChip]。
///
/// 重要：本 App 入口是 `ShadApp`（基于 `WidgetsApp`），**整棵 widget 树没有
/// `Material` 祖先**。而 `ChoiceChip` / `FilterChip` / `ActionChip` /
/// `InputChip` 等 Material 控件都要求 `Material` 祖先，直接放进页面会抛
/// `No Material widget found` 断言。因此本项目一律用 shadcn 的
/// [ShadButton] / [ShadButton.outline] 来表达「选中 / 未选中」态，
/// 既无需 `Material`，又能跟随 shadcn 主题。
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

  const AppChip({
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 6)],
        Text(label),
      ],
    );
    return selected
        ? ShadButton(size: ShadButtonSize.sm, onPressed: onTap, child: child)
        : ShadButton.outline(
            size: ShadButtonSize.sm, onPressed: onTap, child: child);
  }
}

/// 横向可滚动的多选项 chip 行，替代
/// 「`SingleChildScrollView` + `Row` + `ChoiceChip`」这种会报错的写法。
class AppChipRow extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String>? onToggle;
  final bool scrollable;

  const AppChipRow({
    required this.options,
    this.selected = const {},
    this.onToggle,
    this.scrollable = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final chips = options.map(
      (o) => Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: AppChip(
          label: o,
          selected: selected.contains(o),
          onTap: onToggle == null ? null : () => onToggle!(o),
        ),
      ),
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: chips.toList(),
    );
    return scrollable
        ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
        : row;
  }
}
