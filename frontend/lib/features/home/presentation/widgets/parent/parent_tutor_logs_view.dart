import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/presentation/resource.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_scroll_page.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_motion.dart';
import '../../../../tutor/domain/models.dart';
import '../../../../tutor/presentation/providers/tutor_logs_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// AI 答疑记录右栏（F-305）：家长查看选中娃娃的 AI 问答日志。
class ParentTutorLogsView extends ConsumerWidget {
  const ParentTutorLogsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChildProvider);
    if (selected == null) return _emptyState(context);

    final state = ref.watch(tutorLogsNotifierProvider);
    return AppScrollPage(
      children: [
        const SectionTitle('AI 答疑记录'),
        switch (state) {
          ResourceIdle() ||
          ResourceLoading() =>
            const AppLoading(message: '加载答疑记录...'),
          ResourceError() => AppError(message: state.errorOrNull ?? ''),
          ResourceLoaded() => (state.dataOrNull ?? const []).isEmpty
              ? AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Align(alignment: Alignment.topLeft,
                    child: Text('这个娃娃还没有问过 AI 老师',
                        style: AppTheme.textOf(context).bodyLarge),
                  ),
                )
              : Column(
                  children: (state.dataOrNull ?? const <TutorLogModel>[])
                      .map((log) => PopIn(
                            key: ValueKey(log.id),
                            child: AppCard.listRow(
                              margin: const EdgeInsets.only(
                                  bottom: AppSpacing.sm),
                              padding:
                                  const EdgeInsets.all(AppSpacing.md),
                              child: _TutorLogCard(log: log),
                            ),
                          ))
                      .toList(),
                ),
        },
      ],
    );
  }

  /// 未选娃娃时的引导态。
  ///
  /// 收敛到 [AppEmptyState.inline]：此前与 `parent_overview_view.dart` /
  /// `mastery_board.dart` 各手搓了一份「52 色块 + 单行字」，三份画法的撞色、
  /// 描边、色块尺寸互不相同（这里是 cyan 且描边 2px），违反 ADR-0051
  /// 「加载 / 错误 / 空三态共用同一骨架」。
  Widget _emptyState(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: AppCard(
        child: AppEmptyState.inline(
          icon: LucideIcons.sparkles,
          title: '还没有选娃娃',
          message: '在侧栏选一个娃娃，这里就会显示他的答疑记录。',
        ),
      ),
    );
  }
}

class _TutorLogCard extends StatelessWidget {
  final TutorLogModel log;
  const _TutorLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: AppSpacing.sm, top: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.circleHelp,
                    size: 18, color: scheme.onPrimaryContainer),
              ),
              Expanded(
                child: Text('问：${log.question}',
                    style: AppTheme.textOf(context).bodyMedium),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppTags.subject(SubjectAccent.fromName(log.subject)),
              const SizedBox(width: AppSpacing.md),
              log.blocked
                  ? AppBadge.warningChip('已拦截')
                  : AppBadge.successChip('正常'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: AppSpacing.sm, top: 2),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.sparkles,
                    size: 18, color: scheme.onSecondaryContainer),
              ),
              Expanded(
                child: Text('答：${log.answer}',
                    style: AppTheme.textOf(context).bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        )),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
              width: double.infinity, height: 1, color: scheme.outline),
        ],
      ),
    );
  }
}
