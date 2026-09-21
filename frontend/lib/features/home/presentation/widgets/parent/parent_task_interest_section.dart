import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../../../children/providers/children_provider.dart';
import '../../providers/selected_child_provider.dart';

/// 「按兴趣出题」区块：开关 + 娃娃的兴趣主题芯片（WF-4）。
///
/// 开关打开且至少选一个主题时，主题会随生成请求下传，题量在所选主题间轮询均分；
/// 关闭时由后端把娃娃画像里的兴趣轻融入题目——两种模式都是有效行为，不是「没设置」。
///
/// 主题列表由本区块自己从 `childrenNotifierProvider` + `selectedChildProvider` 读：
/// 这是**区块自己的取数**（ADR-0058 §4 的 Section 层），表单不该为了给区块喂数据
/// 而去认识娃娃画像的结构。选中的主题集合仍归表单所有（要参与生成请求）。
class TaskInterestSection extends ConsumerWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final Set<String> selectedThemes;
  final ValueChanged<String> onToggleTheme;

  const TaskInterestSection({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.selectedThemes,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final selected = ref.watch(selectedChildProvider);
    final childState = ref.watch(childrenNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('按兴趣出题',
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ShadSwitch(
              value: enabled,
              checkedTrackColor: app.primary,
              onChanged: onEnabledChanged,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          enabled
              ? '开启后，题目将围绕所选兴趣主题生成情境。'
              : '关闭时，AI 会自动把娃娃画像中的兴趣轻融入题目。',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
        if (enabled) ...[
          const SizedBox(height: AppSpacing.md),
          if (_themesOf(selected, childState).isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: app.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.bubble),
              ),
              child: Text(
                '该娃娃尚未设置兴趣，请先去编辑娃娃资料添加兴趣标签。',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
              ),
            )
          else ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _themesOf(selected, childState)
                  .map(
                    (t) => _ThemeToggle(
                      label: t,
                      selected: selectedThemes.contains(t),
                      onTap: () => onToggleTheme(t),
                    ),
                  )
                  .toList(),
            ),
            if (selectedThemes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text('已选 ${selectedThemes.length} 个主题，题量将在所选主题间轮询均分',
                    style: text.labelSmall?.copyWith(color: app.primary)),
              ),
          ],
        ],
      ],
    );
  }
}

/// 当前娃娃的兴趣主题（受控分类叶子 + 自由文本）。
List<String> _themesOf(SelectedChild? selected, ChildrenState state) {
  if (selected == null || state is! ChildrenLoaded) return const [];
  for (final c in state.children) {
    if (c.id != selected.id || c.interests == null) continue;
    final themes = <String>[...c.interests!.categories];
    final free = c.interests!.freeText;
    if (free != null && free.isNotEmpty) themes.add(free);
    return themes;
  }
  return const [];
}

/// 兴趣主题芯片。视觉风格对齐 [interest_picker.dart] 的同类 chip。
class _ThemeToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppFocusableAction(
      onTap: onTap,
      hoverHighlight: true,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      semanticLabel: label,
      child: AnimatedContainer(
        // 隐式动画**不会**自动尊重 reduce-motion，必须显式归零（ADR-0044）。
        duration: reducedMotionOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          // 选中态允许全填充（ADR-0044 仅 CTA 与选中态可全填）；
          // cyan 是亮块 → 只能配墨黑字（7.94:1）。
          color: selected ? AppBrutal.cyan : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: AppBrutal.ink,
            width: AppElevation.borderWidth,
          ),
          boxShadow: selected ? AppElevation.hard() : AppElevation.none,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(LucideIcons.check, size: 16, color: AppBrutal.ink),
              ),
            Text(label,
                style: text.labelMedium?.copyWith(
                  color: AppBrutal.ink,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}
