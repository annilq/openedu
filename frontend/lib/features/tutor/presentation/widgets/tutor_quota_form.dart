import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';

/// 家长端 AI 管控表单：每日提问上限、时长上限、允许学科多选。
class TutorQuotaForm extends StatelessWidget {
  final TextEditingController askLimitCtrl;
  final TextEditingController minutesLimitCtrl;
  final Set<String> selectedSubjects;
  final ValueChanged<String> onToggleSubject;

  const TutorQuotaForm({
    super.key,
    required this.askLimitCtrl,
    required this.minutesLimitCtrl,
    required this.selectedSubjects,
    required this.onToggleSubject,
  });

  static const _subjects = ['数学', '语文', '英语'];

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: '每日提问上限',
            controller: askLimitCtrl,
            hintText: '次，留空不限',
            keyboardType: TextInputType.number,
            prefixIcon: LucideIcons.listOrdered,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: '每日使用时长上限',
            controller: minutesLimitCtrl,
            hintText: '分钟，留空不限',
            keyboardType: TextInputType.number,
            prefixIcon: LucideIcons.timer,
          ),
          const SizedBox(height: AppSpacing.xl2),
          Text('允许提问的学科（不选 = 不限）', style: text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _subjects
                .map((s) => _SubjectToggle(
                      label: s,
                      selected: selectedSubjects.contains(s),
                      onTap: () => onToggleSubject(s),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SubjectToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SubjectToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 1.5 : 0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(LucideIcons.check,
                    size: 18, color: scheme.onPrimaryContainer),
              ),
            Text(label,
                style: text.labelMedium?.copyWith(
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}
