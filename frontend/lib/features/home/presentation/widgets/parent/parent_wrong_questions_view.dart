import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/presentation/paging.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_paging_footer.dart';
import '../../../../review/presentation/providers/review_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// 家长错题本右栏：查看选中娃娃的错题列表。
///
/// ADR-0053：错题会一直长（答错即入集），此前这个页面用 `SingleChildScrollView`
/// 一次性构建**全部**卡片——几百条错题等于几百张卡全建出来，且接口不分页。
/// 现在改成分页懒加载：首屏一页、触底追加。
class ParentWrongQuestionsView extends ConsumerStatefulWidget {
  const ParentWrongQuestionsView({super.key});

  @override
  ConsumerState<ParentWrongQuestionsView> createState() =>
      _ParentWrongQuestionsState();
}

class _ParentWrongQuestionsState
    extends ConsumerState<ParentWrongQuestionsView> {
  late final ScrollController _scroll = ScrollController();
  VoidCallback? _unbindScroll;

  @override
  void initState() {
    super.initState();
    _unbindScroll = bindPagingOnScroll(
      _scroll,
      () => ref.read(parentWrongQuestionsProvider.notifier).loadMore(),
    );
  }

  @override
  void dispose() {
    _unbindScroll?.call();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedChildProvider);
    if (selected == null) return _emptyState(context);

    final state = ref.watch(parentWrongQuestionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppLayout.contentWide),
              child: const SectionTitle('错题本'),
            ),
          ),
        ),
        Expanded(child: _buildList(state)),
      ],
    );
  }

  Widget _buildList(PagingState<WrongQuestionModel> state) {
    if (state.isLoading || state is PagingIdle) {
      return const AppLoading(message: '加载错题...');
    }
    final error = state.errorOrNull;
    if (error != null) return AppError(message: error, onRetry: _loadMore);
    if (!state.isLoaded) return const AppLoading(message: '加载错题...');
    if (state.items.isEmpty) return _buildEmpty();

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
          sliver: SliverList.builder(
            itemCount: state.items.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard.listRow(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _ParentWrongCard(item: state.items[i]),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: AppLayout.contentWide),
                child: AppPagingFooter(
                  hasMore: state.hasMore,
                  isLoadingMore: state.isLoadingMore,
                  moreError: state.moreError,
                  remaining: state.remaining,
                  onLoadMore: _loadMore,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _loadMore() =>
      ref.read(parentWrongQuestionsProvider.notifier).loadMore();

  Widget _buildEmpty() {
    final scheme = AppTheme.colorsOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentWide),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
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
                const SizedBox(width: AppSpacing.lg),
                Text('暂无错题，继续保持～',
                    style: AppTheme.textOf(context).bodyLarge),
              ],
            ),
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
        padding: const EdgeInsets.all(AppSpacing.md),
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
