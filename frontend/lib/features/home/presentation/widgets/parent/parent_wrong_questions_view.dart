import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/presentation/paging.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_card_list.dart';
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

    // 列数只看可用宽度（ADR-0045）：不碰 MediaQuery / 方向 / 平台。
    return LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppLayout.listGutter,
                AppLayout.listGutter, AppLayout.listGutter, AppSpacing.xl2),
            sliver: AppCardSliver(
              width: constraints.maxWidth,
              itemCount: state.items.length,
              itemBuilder: (_, i) => AppCard.listRow(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _ParentWrongCard(item: state.items[i]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppLayout.listGutter),
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
      ),
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

/// 错题卡（ADR-0053 密度）。
///
/// 此前一张卡把完整题干 + 标准答案 + 整段解析一次全展开，且题干没有行数上限——
/// 一道长题干能撑掉半个屏幕，家长一屏只能看三张半。现在的取舍：
/// - **题干截到 2 行**：单卡高度不可控的直接原因就是它；
/// - **答案保留 1 行**：扫一眼就能判断娃娃错在哪，这是列表里最该留下的信息；
/// - **解析默认折叠**：需要细看时点开，不占列表的默认高度（≈250 → ≈150）。
class _ParentWrongCard extends StatefulWidget {
  final WrongQuestionModel item;
  const _ParentWrongCard({required this.item});

  @override
  State<_ParentWrongCard> createState() => _ParentWrongCardState();
}

class _ParentWrongCardState extends State<_ParentWrongCard> {
  /// 展开状态是「这一张卡的事」，不进 provider：翻页后卡片重建，折叠回去是对的。
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scheme = AppTheme.colorsOf(context);
    final hasExplanation = item.explanation.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.stem,
          style: AppTheme.textOf(context).bodyLarge,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
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
                  // 答案一行：它是「扫一眼」的信息，长答案点开卡片看全文。
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.textOf(context).bodyMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
        if (hasExplanation)
          AppTextAction(
            label: _expanded ? '收起解析' : '查看解析',
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        if (hasExplanation && _expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text('解析：${item.explanation}',
                style: AppTheme.textOf(context).bodyMedium),
          ),
      ],
    );
  }
}
