import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_motion.dart';

/// 选项卡片：字母圆圈 + 文案 + 选中描边/勾选。
///
/// 合并自 practice `_OptionTile` 与 review `_ReviewOptionTile`：统一用 [PressScale]
/// 作为按压反馈（项目手势标准），[disabled] 承载提交中禁用态（判题时不可改答）。
class AppOptionTile extends StatelessWidget {
  final int index;
  final String text;
  final bool selected;
  final VoidCallback? onTap;
  final bool disabled;

  const AppOptionTile({
    super.key,
    required this.index,
    required this.text,
    required this.selected,
    this.onTap,
    this.disabled = false,
  });

  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final letter = index < _letters.length ? _letters[index] : '${index + 1}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: PressScale(
        onTap: disabled ? null : onTap,
        downScale: 0.975,
        upDuration: const Duration(milliseconds: 300),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: selected ? Border.all(color: scheme.primary, width: 2) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : scheme.surfaceSunken,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: text.labelLarge?.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    this.text,
                    style: text.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: AppSpacing.md),
                  child: Icon(LucideIcons.checkCircle2,
                      color: scheme.primary, size: 24),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
