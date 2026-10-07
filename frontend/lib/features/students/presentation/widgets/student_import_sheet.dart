import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/domain/models/student_import_result.dart';

/// 导入结果浮层（ticket 06）：非 Material（保持无 Material 祖先），分区展示
/// 创建 / 跳过 / 逐行错误原因。覆于全屏，点遮罩或关闭按钮消失。
class StudentImportSheet extends StatelessWidget {
  final StudentImportResultModel result;
  final VoidCallback onDismiss;

  const StudentImportSheet({
    super.key,
    required this.result,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final r = result;
    return Stack(
      children: [
        Positioned.fill(
          child: AppFocusableAction(
            onTap: onDismiss,
            semanticLabel: '关闭',
            child: Container(color: scheme.scrim),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: scheme.outline,
                width: AppElevation.borderWidth,
              ),
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Text('导入结果', style: text.titleMedium),
                      const Spacer(),
                      AppTextAction(label: '关闭', onPressed: onDismiss),
                    ],
                  ),
                ),
                Container(height: 1, color: scheme.outline),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      _SummaryRow(
                        label: '成功创建',
                        value: r.created,
                        background: scheme.accent,
                        foreground: scheme.onAccent,
                      ),
                      _SummaryRow(
                        label: '跳过（冲突 / 缺列）',
                        value: r.skipped,
                        background: scheme.surfaceSunken,
                        foreground: scheme.onSurface,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (r.errors.isEmpty)
                        Text(
                          '全部导入成功，无错误行。',
                          style: text.labelMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      for (final e in r.errors)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(LucideIcons.alertCircle,
                                  size: 16, color: scheme.onSurfaceVariant),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  '第 ${e.row} 行：${e.reason}',
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int value;
  final Color background;
  final Color foreground;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              '$value',
              style: text.labelMedium
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: text.labelMedium),
        ],
      ),
    );
  }
}
