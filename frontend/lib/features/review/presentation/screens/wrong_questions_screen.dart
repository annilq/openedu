import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/scene_spec.dart';
import '../../../../shared/presentation/paging.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_card_list.dart';
import '../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_paging_footer.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../providers/review_notifier.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_tags.dart';

String _fmtDate(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// 学生端错题本：v2 redesign - 用 AppTags 语义化、SectionTitle、空状态加图标。
class WrongQuestionsScreen extends ConsumerStatefulWidget {
  final bool showBack;
  const WrongQuestionsScreen({super.key, this.showBack = true});

  @override
  ConsumerState<WrongQuestionsScreen> createState() =>
      _WrongQuestionsScreenState();
}

class _WrongQuestionsScreenState extends ConsumerState<WrongQuestionsScreen> {
  /// 触底自动加载下一页（ADR-0053）：错题本会一直长，一次拉全量不现实。
  late final ScrollController _scroll = ScrollController();
  VoidCallback? _unbindScroll;

  @override
  void initState() {
    super.initState();
    _unbindScroll = bindPagingOnScroll(
      _scroll,
      () => ref.read(childWrongQuestionsProvider.notifier).loadMore(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(childWrongQuestionsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _unbindScroll?.call();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() {
    return ref.read(childWrongQuestionsProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(childWrongQuestionsProvider);
    final scheme = AppTheme.colorsOf(context);

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(
              title: '我的错题本',
              showBack: widget.showBack,
              trailing: ShadButton.ghost(
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                backgroundColor: const Color(0x00000000),
                hoverBackgroundColor: scheme.surfaceContainerHigh,
                pressedBackgroundColor: scheme.surfaceContainer,
                onPressed: _refresh,
                child: Icon(
                  LucideIcons.refreshCw,
                  color: scheme.onSurface,
                  size: 20,
                ),
              ),
            ),
            Expanded(child: _buildBody(state)),
          ],
        ),
      ),
    );
  }

  void _loadMore() =>
      ref.read(childWrongQuestionsProvider.notifier).loadMore();

  Widget _buildBody(PagingState<WrongQuestionModel> state) {
    if (state is PagingIdle || state.isLoading) {
      return const AppLoading(message: '加载错题...');
    }
    final error = state.errorOrNull;
    if (error != null) {
      return AppError(
        message: error,
        onRetry: () => ref.read(childWrongQuestionsProvider.notifier).load(),
      );
    }
    if (!state.isLoaded) return const AppLoading(message: '加载错题...');
    if (state.items.isEmpty) return _buildEmptyView();

    final items = state.items;
    // 列数只看可用宽度（ADR-0045）：不碰 MediaQuery / 方向 / 平台。
    return LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppLayout.listGutter,
                AppLayout.listGutter, AppLayout.listGutter, 0),
            sliver: AppCardSliver(
              width: constraints.maxWidth,
              itemCount: items.length,
              itemBuilder: (ctx, i) => PopIn(
                // key 稳定 → PopIn 只对「新滑入」的行重放，复用行不闪。
                key: ValueKey(items[i].id),
                // 学科色条改为卡片左边框（见 _WrongQuestionCard），不再需要
                // IntrinsicHeight 给有界高度——否则会触发卡片内 SceneInterpreter
                // 的 LayoutBuilder 做 intrinsic 计算而抛异常（ADR-0061 §V）。
                child: _WrongQuestionCard(item: items[i]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppLayout.listGutter),
              child: AppPagingFooter(
                hasMore: state.hasMore,
                isLoadingMore: state.isLoadingMore,
                moreError: state.moreError,
                remaining: state.remaining,
                onLoadMore: _loadMore,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    final scheme = AppTheme.colorsOf(context);
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentEmpty),
          child: PopIn(
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(28),
                      // 色块 = 2px 墨黑描边 + 硬阴影（ADR-0044）。
                      border: Border.all(
                          color: AppBrutal.ink, width: AppElevation.borderWidth),
                      boxShadow: AppElevation.hard(),
                    ),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.badgeCheck,
                        size: 44, color: scheme.onTertiaryContainer),
                  ),
                  const SizedBox(height: AppSpacing.xl2),
                  Text('还没有错题',
                      textAlign: TextAlign.start,
                      style: AppTheme.textOf(context).titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text('继续保持，做题仔细一点就不会错啦～',
                      textAlign: TextAlign.start,
                      style: AppTheme.textOf(context).bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 错题列表行：用 [AppCard.listRow]（1px 墨黑描边、无阴影）降噪，
/// 仅左侧 4px 学科色条 + 学科 chip 表达身份（不整行填充，ADR-0044）。
class _WrongQuestionCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _WrongQuestionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final subjectKey = SubjectAccent.fromName(item.subject);
    final subjectColor = SubjectAccent.forContext(subjectKey, context).accent;
    // 场景规格经唯一解析入口（ADR-0091）：旧形 / 畸形 → 无图形区（不猜字段）。
    final spec =
        item.sceneSpec == null ? null : SceneSpec.tryParse(item.sceneSpec!);
    // 左侧 4px 学科色条的表达方式变迁（ADR-0061 §V / ADR-0044）：
    // 1) 最早用 Row(stretch)+IntrinsicHeight 给色条撑满行高，但 IntrinsicHeight
    //    会向子树取 intrinsic 高度，而卡片内 SceneInterpreter 的 LayoutBuilder
    //    拒绝 speculative intrinsic 计算 → 抛「LayoutBuilder does not support
    //    returning intrinsic dimensions」。
    // 2) 改为把色条画成卡片「左边框」——边框随卡片自然撑满行高，绕开了上述崩溃。
    // 3) 但 ShadCard 把 border 直接喂给内部 BoxDecoration，而 BoxDecoration 在已设
    //    borderRadius 时要求四条边同色，否则 paint 抛「A borderRadius can only be
    //    given on borders with uniform colors」。本仓 card 一律带圆角，所以非均匀
    //    边框必崩（错题本因此白屏）。
    // 现改为卡片内 Stack + 左侧 ColoredBox 画色条，靠 ShadCard 自身 clip 裁圆角：
    // 既不再引入 IntrinsicHeight，也不再把非均匀边框塞进 ShadCard，两头都避开。
    return AppCard.listRow(
      // 行距由 AppCardSliver 统一给（此前这里是裸数字 6，三个页面三种行距）。
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          children: [
            // 学科色条：画在卡片内容左侧，靠 ClipRRect 自动裁成圆角。
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: subjectColor),
            ),
            Padding(
              // 左侧多留 4px 给色条，其余三边保持 md。
              padding: const EdgeInsets.only(
                left: AppSpacing.md + 4,
                top: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.stem,
                    style: AppTheme.textOf(context).titleSmall,
                    // 长题干不加行数上限会撑掉半屏（ADR-0053）。
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      // 学科三重编码 chip（色 + 几何标记 + 文字）。
                      AppTags.subject(subjectKey),
                      AppTags.info(item.knowledgePoint),
                      AppTags.warning('错过 ${item.wrongCount} 次'),
                      AppTags.normal('复习阶段 ${item.reviewStage}'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('最近答错：${_fmtDate(item.firstWrongAt)}',
                            style: AppTheme.textOf(context).labelSmall),
                        if (item.dueAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('下次复习：${_fmtDate(item.dueAt)}',
                                style: AppTheme.textOf(context)
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600,
                                    )),
                          ),
                      ],
                    ),
                  ),
                  if (spec != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppTags.info('交互讲解'),
                    const SizedBox(height: AppSpacing.sm),
                    SceneInterpreter(spec: spec),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
