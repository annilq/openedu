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
import '../../../../../shared/widgets/app_toast.dart';
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

  /// 是否在看「已掌握」分区（ADR-0053 P2）。
  ///
  /// 做成模式切换而不是「列表底部再嵌一个列表」：两条列表都要分页、都要触底追加，
  /// 嵌在一起就得处理两层滚动与两层触底，收益却只是省一次点击。
  bool _showGraduated = false;

  @override
  void initState() {
    super.initState();
    _unbindScroll = bindPagingOnScroll(_scroll, _loadMore);
  }

  /// 触底追加的是**当前正在看的那一条**列表。
  void _loadMore() {
    if (_showGraduated) {
      ref.read(parentGraduatedWrongQuestionsProvider.notifier).loadMore();
    } else {
      ref.read(parentWrongQuestionsProvider.notifier).loadMore();
    }
  }

  void _switchGraduated(bool value) {
    if (value == _showGraduated) return;
    setState(() => _showGraduated = value);
    final childId = ref.read(selectedChildProvider)?.id;
    if (childId == null) return;
    if (value) {
      ref
          .read(parentGraduatedWrongQuestionsProvider.notifier)
          .load(childId);
    } else {
      ref.read(parentWrongQuestionsProvider.notifier).load(childId);
    }
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

    // 两个分区各自一份状态：查询条件不同（scope=active / graduated），
    // 合成一份会让「翻页」和「切分区」互相踩。
    final state = _showGraduated
        ? ref.watch(parentGraduatedWrongQuestionsProvider)
        : ref.watch(parentWrongQuestionsProvider);
    final graduatedTotal = graduatedTotalOf(ref.watch(parentWrongQuestionsProvider));
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
              child: _Header(
                showGraduated: _showGraduated,
                graduatedTotal: graduatedTotal,
                onSwitch: _switchGraduated,
              ),
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
                child: _ParentWrongCard(
                  item: state.items[i],
                  // 「已掌握」分区只读：可重新加入复习，但不提供「掌握了」之外的解读。
                  onRejoin: _showGraduated ? () => _rejoin(state.items[i]) : null,
                ),
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

  /// 重新加入复习：成功后两条列表都会由 provider 刷新（它会从「已掌握」里消失）。
  Future<void> _rejoin(WrongQuestionModel item) async {
    final childId = ref.read(selectedChildProvider)?.id;
    if (childId == null) return;
    try {
      await ref
          .read(rejoinWrongQuestionProvider)(childId, item.id);
      if (mounted) AppToast.show(context, '已重新加入复习');
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString());
    }
  }

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
/// 标题行 = 分区切换器（ADR-0053 P2）：默认「错题本」，可切到「已掌握（N）」。
///
/// 用 chip 而不是文字链：它和题库页的年级 / 归档 chip 是同一种筛选语言，
/// 键盘可达、有明确的选中态。
class _Header extends StatelessWidget {
  const _Header({
    required this.showGraduated,
    required this.graduatedTotal,
    required this.onSwitch,
  });

  final bool showGraduated;
  final int graduatedTotal;
  final void Function(bool) onSwitch;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SectionTitle(showGraduated ? '已掌握' : '错题本'),
        if (graduatedTotal > 0 || showGraduated)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: showGraduated
                ? ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () => onSwitch(false),
                    child: const Text('返回未掌握'),
                  )
                : ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () => onSwitch(true),
                    child: Text('已掌握（$graduatedTotal）'),
                  ),
          ),
      ],
    );
  }
}

class _ParentWrongCard extends StatefulWidget {
  final WrongQuestionModel item;

  /// 非空时卡片底部出现「重新加入复习」（只有「已掌握」分区有）。
  final VoidCallback? onRejoin;
  const _ParentWrongCard({required this.item, this.onRejoin});

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
        if (widget.onRejoin != null)
          AppTextAction(
            label: '重新加入复习',
            onPressed: widget.onRejoin,
            semanticLabel: '重新加入复习',
          ),
      ],
    );
  }
}
