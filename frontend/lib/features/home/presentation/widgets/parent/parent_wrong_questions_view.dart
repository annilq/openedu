import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../review/presentation/providers/review_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// 家长错题本右栏：查看选中娃娃的错题列表。
class ParentWrongQuestionsView extends ConsumerWidget {
  const ParentWrongQuestionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChildProvider);
    if (selected == null) return _emptyState(context);

    final state = ref.watch(parentWrongQuestionsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('错题本'),
              switch (state) {
                WrongQuestionsInitial() ||
                WrongQuestionsLoading() =>
                  const AppLoading(message: '加载错题...'),
                WrongQuestionsError() => AppError(message: state.message),
                WrongQuestionsLoaded() => state.items.isEmpty
                    ? AppCard(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Align(alignment: Alignment.topLeft,
                          child: Text('暂无错题，继续保持～',
                              style: AppTheme.textOf(context).bodyLarge),
                        ),
                      )
                    : Column(
                        children: [
                          for (final item in state.items)
                            AppCard(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              margin: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm),
                              child: _ParentWrongCard(item: item),
                            ),
                        ],
                      ),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    // 仅水平居中、垂直贴顶：避免卡片在内容区上下居中（「局中」观感）。
    return Align(
      alignment: Alignment.topLeft,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.bookOpen,
                  size: 28, color: scheme.onErrorContainer),
            ),
            const SizedBox(width: AppSpacing.xl),
            Text('请先在侧栏选择娃娃', style: AppTheme.textOf(context).bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _ParentWrongCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _ParentWrongCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.stem, style: AppTheme.textOf(context).bodyLarge),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppTags.normal(item.knowledgePoint),
            AppTags.warning('错过 ${item.wrongCount} 次'),
            AppTags.info('复习阶段 ${item.reviewStage}'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.checkCircle2,
                  size: 20, color: scheme.onTertiaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '标准答案：${item.answer ?? '—'}',
                  style: AppTheme.textOf(context).bodyMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
        if (item.explanation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text('解析：${item.explanation}',
                style: AppTheme.textOf(context).bodyMedium),
          ),
      ],
    );
  }
}
