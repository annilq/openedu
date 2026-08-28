import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../tutor/presentation/providers/tutor_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// AI 答疑记录右栏（F-305）：家长查看选中娃娃的 AI 问答日志。
class ParentTutorLogsView extends ConsumerWidget {
  const ParentTutorLogsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChildProvider);
    if (selected == null) return _emptyState(context);

    final state = ref.watch(tutorLogsNotifierProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('AI 答疑记录'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: switch (state) {
                  TutorLogsInitial() || TutorLogsLoading() =>
                    const AppLoading(message: '加载答疑记录...'),
                  TutorLogsError() => AppError(message: state.message),
                  TutorLogsLoaded() => state.logs.isEmpty
                      ? AppCard(
                          padding: const EdgeInsets.all(AppSpacing.xl3),
                          child: Center(
                            child: Text('这个娃娃还没有问过 AI 老师',
                                style: AppTheme.textOf(context).bodyLarge),
                          ),
                        )
                      : AppCard(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: state.logs
                                .map((log) => _TutorLogCard(log: log))
                                .toList(),
                          ),
                        ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Center(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.sparkles, size: 28,
                  color: scheme.onSecondaryContainer),
            ),
            const SizedBox(width: AppSpacing.xl),
            Text('请先在侧栏选择娃娃',
                style: AppTheme.textOf(context).bodyLarge),
          ],
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
                width: 32, height: 32,
                margin: const EdgeInsets.only(right: AppSpacing.sm, top: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.circleHelp, size: 18,
                    color: scheme.onPrimaryContainer),
              ),
              Expanded(
                child: Text('问：${log.question}',
                    style: AppTheme.textOf(context).bodyMedium),
              ),
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
                width: 32, height: 32,
                margin: const EdgeInsets.only(right: AppSpacing.sm, top: 2),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.sparkles, size: 18,
                    color: scheme.onSecondaryContainer),
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
          Container(width: double.infinity, height: 1, color: scheme.outlineVariant),
        ],
      ),
    );
  }
}
