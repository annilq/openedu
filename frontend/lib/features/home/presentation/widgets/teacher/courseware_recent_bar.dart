import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../courseware/presentation/pages/courseware_present_page.dart';
import '../../../../courseware/providers/courseware_provider.dart';

/// 「最近课件」回执（ADR-0067 §3.8 强制补偿项）。
///
/// 课件入口藏得深（资料库 → 知识点管理 → 三选范围 → 找知识点 → 点课件），课前最慌的
/// 几分钟里 5 步会劝退人，所以顶部给一条直达演示态的捷径。无课件时不占位——不制造
/// 「空档」噪音，也避免暗示「你本该有」。
class CoursewareRecentBar extends ConsumerWidget {
  const CoursewareRecentBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(coursewareRecentProvider);
    return recent.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) {
        // 回执只是便捷入口，拉取失败不应阻断整页；静默收起即可。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            AppToast.show(context, '读取最近课件失败：$error');
          }
        });
        return const SizedBox.shrink();
      },
      data: (cw) {
        if (cw == null) return const SizedBox.shrink();
        final app = AppTheme.colorsOf(context);
        final text = AppTheme.textOf(context);
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: app.primary.withValues(alpha: 0.1),
            border: Border.all(color: app.primary, width: AppElevation.borderWidth),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.history, size: AppSpacing.lg, color: app.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '继续上次：${cw.displayTitle}',
                  style: text.bodyMedium?.copyWith(color: app.primary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppFocusableAction(
                semanticLabel: '继续上次课件 ${cw.displayTitle}',
                hoverHighlight: true,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CoursewarePresentPage(coursewareId: cw.id),
                  ),
                ),
                child: Text(
                  '开始讲课',
                  style: text.labelLarge?.copyWith(color: app.primary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
