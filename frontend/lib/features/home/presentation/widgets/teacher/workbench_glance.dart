import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../analytics/domain/models/analytics_models.dart';
import '../../../../analytics/presentation/providers/analytics_summary_provider.dart';
import '../../../../../shared/presentation/shell_navigation.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/load_once.dart';
import '../../../../../shared/widgets/analytics_charts.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_badge.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_section_title.dart';
import '../../../../../shared/widgets/app_tags.dart' hide AppBadge;
import '../../../../../shared/widgets/responsive_grid.dart';
import '../../providers/task_form_prefill.dart';

/// 工作台速览层（ADR-0075 §2.2 / ticket 03）。
///
/// 进入即看的教师整体概览，作用域固定 `all`：[analyticsSummaryProvider] 取数，与
/// 分析层 [analyticsNotifierProvider] 彻底分离（见该 provider 注释）。四块图表：
///  1. 掌握度概览环形（已掌握 vs 剩余，中心 `X / Y`）；
///  2. 薄弱知识点横向条形（按 `activeWrong` 降序、accuracy 分级配色）+「就这个出题」钩子；
///  3. 正确率分组条（练习 / 复习 / 总体，按学科）；
///  4. 错题分布堆叠条（活跃 vs 已毕业，按学科）。
///
/// 孤儿「未知」错题组以警示色条显式保留（ADR-0064 / ADR-0070 §2.4.3），不混入有效分组。
///
/// [onDrill] 为薄弱知识点点击钻取回调（落到分析层并预选该知识点）；本层只触发回调、
/// 具体钻取行为由组合页（ticket 05）接线。
class WorkbenchGlance extends ConsumerWidget {
  final void Function(String knowledgePoint)? onDrill;

  const WorkbenchGlance({super.key, this.onDrill});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analyticsSummaryProvider);
    ref.loadWhenIdle(
      analyticsSummaryProvider,
      (s) => s is AnalyticsSummaryInitial,
      () => ref.read(analyticsSummaryProvider.notifier).load(),
    );

    if (state is AnalyticsSummaryLoading || state is AnalyticsSummaryInitial) {
      return const AppLoading.skeletonInline(skeletonLines: 4);
    }
    if (state is AnalyticsSummaryError) {
      return AppError(
        message: state.message,
        onRetry: () => ref.read(analyticsSummaryProvider.notifier).load(),
      );
    }
    final loaded = state as AnalyticsSummaryLoaded;
    return AppResponsiveGrid(
      colsWide: 2,
      children: [
        _MasteryDonutCard(mastery: loaded.mastery, wrong: loaded.wrong),
        _WeakPointsChartCard(
          mastery: loaded.mastery,
          onDrill: onDrill,
          ref: ref,
        ),
        _AccuracyChartCard(resp: loaded.accuracy),
        _WrongDistributionChartCard(resp: loaded.wrong),
      ],
    );
  }
}

/// 正确率 → 语义色（红 <60% / 琥珀 60–85% / 绿 >85%），与 ADR-0075 §2.3 一致。
Color _gradeColor(AppColors c, double accuracy) {
  if (accuracy < 0.6) return c.semanticError;
  if (accuracy < 0.85) return c.semanticWarning;
  return c.semanticPositive;
}

String _pct(double v) => '${(v * 100).round()}%';

/// 掌握度环形：已掌握 vs 剩余，中心 `X / Y`。
class _MasteryDonutCard extends StatelessWidget {
  final MasteryResp mastery;
  final WrongDistributionResp wrong;
  const _MasteryDonutCard({required this.mastery, required this.wrong});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final total = mastery.totalKnowledgePoints;
    final mastered = mastery.masteredCount;
    final remaining = (total - mastered).clamp(0, total);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            '掌握度概览',
            trailing: AppBadge(
              label: '活跃错题 ${wrong.totalActive}',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (total == 0)
            const AppEmptyState.inline(
              icon: LucideIcons.pieChart,
              title: '暂无知识点掌握数据',
              message: '派发并作答任务后，这里会汇总掌握度。',
            )
          else
            Row(
              children: [
                AppDonutChart(
                  segments: [
                    DonutSegment(value: mastered.toDouble(), color: scheme.accent),
                    DonutSegment(
                      value: remaining.toDouble(),
                      color: scheme.surfaceSunken,
                    ),
                  ],
                  centerTop: '$mastered',
                  centerBottom: '/ $total',
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已掌握 $mastered / $total 个知识点',
                        style: AppTheme.textOf(context)
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurface),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${_pct(total > 0 ? mastered / total : 0)} 掌握率',
                        style: AppTheme.textOf(context)
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 薄弱知识点：横向条形（accuracy 分级配色）+「就这个出题」钩子 + 点击钻取。
class _WeakPointsChartCard extends StatelessWidget {
  final MasteryResp mastery;
  final void Function(String knowledgePoint)? onDrill;
  final WidgetRef ref;
  const _WeakPointsChartCard({
    required this.mastery,
    required this.ref,
    this.onDrill,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final weak = [...mastery.items]
      ..sort((a, b) => b.activeWrong.compareTo(a.activeWrong));
    final items = weak.where((m) => m.activeWrong > 0).take(6).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('薄弱知识点'),
          const SizedBox(height: AppSpacing.xs),
          if (items.isEmpty)
            const AppEmptyState.inline(
              icon: LucideIcons.checkCircle2,
              title: '暂无薄弱知识点',
              message: '目前没有活跃错题，继续保持～',
            )
          else
            for (final it in items)
              _WeakPointRow(
                item: it,
                scheme: scheme,
                ref: ref,
                onDrill: onDrill,
              ),
        ],
      ),
    );
  }
}

class _WeakPointRow extends StatelessWidget {
  final MasteryGroup item;
  final AppColors scheme;
  final WidgetRef ref;
  final void Function(String knowledgePoint)? onDrill;

  const _WeakPointRow({
    required this.item,
    required this.scheme,
    required this.ref,
    this.onDrill,
  });

  @override
  Widget build(BuildContext context) {
    final grade = _gradeColor(scheme, item.accuracy);
    final row = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppTags.subject(
                SubjectAccent.fromName(item.subject),
                label: item.subject,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.knowledgePoint,
                  style: AppTheme.textOf(context).bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (item.activeWrong / 20).clamp(0.05, 1.0),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: grade,
                border: Border.all(
                  color: scheme.outline,
                  width: AppElevation.borderWidthSm,
                ),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                '正确率 ${_pct(item.accuracy)} · ${item.activeWrong} 题待复习',
                style: AppTheme.textOf(context)
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              AppTextAction(
                label: '就这个出题',
                semanticLabel: '就${item.knowledgePoint}出题',
                onPressed: () {
                  ref.read(taskFormPrefillProvider.notifier).state =
                      TaskFormPrefill(knowledgePoint: item.knowledgePoint);
                  ref
                      .read(shellNavigationProvider.notifier)
                      .request(ShellDestination.teacherCreateTask);
                },
              ),
            ],
          ),
        ],
      ),
    );
    if (onDrill == null) return row;
    return AppFocusableAction(
      onTap: () => onDrill!(item.knowledgePoint),
      semanticLabel: '钻取到${item.knowledgePoint}的分析',
      child: row,
    );
  }
}

/// 正确率分组条（练习 / 复习 / 总体，按学科）。
class _AccuracyChartCard extends StatelessWidget {
  final AccuracyResp resp;
  const _AccuracyChartCard({required this.resp});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('正确率'),
          const SizedBox(height: AppSpacing.sm),
          if (resp.groups.isEmpty && resp.orphanCount == 0)
            const AppEmptyState.inline(
              icon: LucideIcons.target,
              title: '暂无作答记录',
              message: '派发并作答任务后，这里会汇总正确率。',
            )
          else ...[
            AppGroupedBarChart(
              data: [
                for (final g in resp.groups)
                  GroupedBarDatum(
                    label: g.group,
                    series: [
                      BarSeries(
                        name: '练习',
                        value: g.practice.accuracy * 100,
                        color: scheme.accent,
                      ),
                      BarSeries(
                        name: '复习',
                        value: g.review.accuracy * 100,
                        color: scheme.semanticWarning,
                      ),
                      BarSeries(
                        name: '总体',
                        value: g.overall.accuracy * 100,
                        color: scheme.semanticPositive,
                      ),
                    ],
                  ),
              ],
              unit: '%',
            ),
          ],
        ],
      ),
    );
  }
}

/// 错题分布堆叠条（活跃 vs 已毕业，按学科）+ 孤儿警示。
class _WrongDistributionChartCard extends StatelessWidget {
  final WrongDistributionResp resp;
  const _WrongDistributionChartCard({required this.resp});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            '错题分布',
            trailing: AppBadge(
              label: '共 ${resp.total} 道',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '活跃 ${resp.totalActive} · 已毕业 ${resp.totalGraduated}',
            style: AppTheme.textOf(context)
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (resp.groups.isEmpty && resp.orphanCount == 0)
            const AppEmptyState.inline(
              icon: LucideIcons.barChart3,
              title: '本范围暂无错题',
              message: '派发并作答任务后，这里会汇总错题分布。',
            )
          else ...[
            AppStackedBarChart(
              data: [
                for (final g in resp.groups)
                  StackedBarDatum(
                    label: g.group,
                    segments: [
                      StackedSegment(
                        name: '活跃',
                        value: g.active.toDouble(),
                        color: scheme.semanticError,
                      ),
                      StackedSegment(
                        name: '已毕业',
                        value: g.graduated.toDouble(),
                        color: scheme.semanticPositive,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
