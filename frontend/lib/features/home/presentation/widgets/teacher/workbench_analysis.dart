import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../analytics/domain/models/analytics_models.dart';
import '../../../../analytics/presentation/providers/analytics_notifier.dart';
import '../../../../analytics/presentation/providers/analytics_notifier_provider.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/load_once.dart';
import '../../../../../shared/widgets/analytics_charts.dart';
import '../../../../../shared/widgets/app_badge.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_chip.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_section_title.dart';
import '../../../../../shared/widgets/responsive_grid.dart';

/// 工作台分析层（ADR-0075 §2.2 / ticket 04，工作台优化）。
///
/// 由 [analyticsScreen] 迁移而来：保留作用域（all / class）+ 维度四选（学科 / 年级 /
/// 学期 / 知识点）下钻。正确率（分组条）已在速览层展示、此处刻意去重，故本层只渲染
/// 两份聚合（`错题分布` 堆叠条 / `掌握度` 横向条），均以图表适配器渲染、替换原纯文字
/// `_MetricRow`，并在宽屏并排（[AppResponsiveGrid]）。口径严格对照 ADR-0070：孤儿「未知」
/// 错题组以温和的琥珀提示条显式保留、不混入有效分组；年级维度标注「题目年级」；空学期
/// 由后端收敛为「整学年」，界面原样展示。
///
/// [onDrill] 为掌握度横向条点击钻取回调（参数即知识点名），由组合页（ticket 05）接线。
class WorkbenchAnalysis extends ConsumerWidget {
  final void Function(String knowledgePoint)? onDrill;

  const WorkbenchAnalysis({super.key, this.onDrill});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analyticsNotifierProvider);
    ref.loadWhenIdle(
      analyticsNotifierProvider,
      (s) => s is AnalyticsInitial,
      () => ref.read(analyticsNotifierProvider.notifier).init(),
    );

    if (state is AnalyticsInitial || state is AnalyticsLoading) {
      return const AppLoading();
    }
    if (state is AnalyticsError) {
      return AppError(
        message: state.message,
        onRetry: () => ref.read(analyticsNotifierProvider.notifier).init(),
      );
    }
    if (state is! AnalyticsLoaded) {
      return const AppEmptyState(
        icon: LucideIcons.barChart3,
        title: '暂无数据',
        message: '派发并作答任务后，这里会汇总学情分析。',
      );
    }
    final loaded = state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnalysisControls(
          state: loaded,
          onScope: ref.read(analyticsNotifierProvider.notifier).setScope,
          onDimension:
              ref.read(analyticsNotifierProvider.notifier).setDimension,
          onClass: ref.read(analyticsNotifierProvider.notifier).setClass,
        ),
        const SizedBox(height: AppSpacing.md),
        AppResponsiveGrid(
          colsWide: 2,
          children: [
            _WrongDistributionChartCard(resp: loaded.wrong),
            _MasteryChartCard(
              resp: loaded.mastery,
              onDrill: onDrill,
            ),
          ],
        ),
      ],
    );
  }
}

/// 控制条：作用域两态 + 班级选择器 + 四维切换。
class _AnalysisControls extends StatelessWidget {
  final AnalyticsLoaded state;
  final void Function(String) onScope;
  final void Function(String) onDimension;
  final void Function(String?) onClass;

  const _AnalysisControls({
    required this.state,
    required this.onScope,
    required this.onDimension,
    required this.onClass,
  });

  static const _scopes = [
    ('all', '全体学生'),
    ('class', '单个班级'),
  ];
  static const _dims = [
    ('subject', '学科'),
    ('grade', '年级'),
    ('semester', '学期'),
    ('knowledge_point', '知识点'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('统计范围'),
          _ChipRow(
            options: _scopes,
            selected: state.scope,
            onTap: onScope,
          ),
          if (state.scope == 'class') ...[
            const SizedBox(height: AppSpacing.sm),
            AppPickerField<String>(
              label: '选择班级',
              values: state.classes.map((c) => c.id).toList(),
              labels: state.classes
                  .map((c) => '${c.name}（${c.studentCount}人）')
                  .toList(),
              value: state.classId,
              placeholder: '选择班级',
              onChanged: (v) => onClass(v),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const SectionTitle('分组维度'),
          _ChipRow(
            options: _dims,
            selected: state.dimension,
            onTap: onDimension,
          ),
          if (state.dimension == 'grade') ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '年级按「题目」归类（即试卷所属年级），非学生当前所在年级。',
              style: AppTheme.textOf(context)
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单选 chip 行（作用域 / 维度共用）。
class _ChipRow extends StatelessWidget {
  final List<(String, String)> options;
  final String selected;
  final void Function(String) onTap;

  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: AppChip(
                label: label,
                selected: selected == value,
                onTap: () => onTap(value),
              ),
            ),
        ],
      ),
    );
  }
}

String _pct(double v) => '${(v * 100).round()}%';

Color _gradeColor(AppColors c, double accuracy) {
  if (accuracy < 0.6) return c.semanticError;
  if (accuracy < 0.85) return c.semanticWarning;
  return c.semanticPositive;
}

/// 错题分布：堆叠条（活跃 vs 已毕业）+ 孤儿警示。
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
            if (resp.orphanCount > 0) _OrphanWarnRow(count: resp.orphanCount),
          ],
        ],
      ),
    );
  }
}

/// 掌握度：横向条（按活跃错题降序、accuracy 分级配色）+ level 徽章 + 孤儿警示。
class _MasteryChartCard extends StatelessWidget {
  final MasteryResp resp;
  final void Function(String knowledgePoint)? onDrill;
  const _MasteryChartCard({required this.resp, this.onDrill});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final sorted = [...resp.items]
      ..sort((a, b) => b.activeWrong.compareTo(a.activeWrong));
    // 横向条列表不设上限会随知识点数线性拉长页面；与速览 top6 同一纪律，
    // 默认展示活跃错题最多的 12 项，余下以静默脚注提示（不截断数据，仅收口高度）。
    final items = sorted.take(12).toList();
    final overflow = sorted.length - items.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            '掌握度',
            trailing: AppBadge(
              label: '已掌握 ${resp.masteredCount}/${resp.totalKnowledgePoints}',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty && resp.orphanCount == 0)
            const AppEmptyState.inline(
              icon: LucideIcons.graduationCap,
              title: '本范围暂无知识点掌握数据',
              message: '派发并作答任务后，这里会汇总掌握度。',
            )
          else ...[
            AppBarChart(
              data: [
                for (final it in items)
                  BarDatum(
                    label: it.knowledgePoint,
                    value: it.activeWrong.toDouble(),
                    color: _gradeColor(scheme, it.accuracy),
                    caption: '正确率 ${_pct(it.accuracy)}'
                        '${it.level.isNotEmpty ? ' · $it.level' : ''}',
                  ),
              ],
              onTap: onDrill == null
                  ? null
                  : (i) => onDrill!(items[i].knowledgePoint),
            ),
            if (overflow > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '仅展示活跃错题最多的 $items.length 项；其余 $overflow 个知识点可在维度切换后查看。',
                  style: AppTheme.textOf(context)
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 孤儿「未知」错题：数据健康提示（琥珀色，非报错红），显式保留、不混入有效分组
/// （ADR-0064 / ADR-0070 §2.4.3）。降级为温和提示，避免与真正错误混淆；仅错题分布
/// 卡展示一次，不在多个卡片内重复出现。
class _OrphanWarnRow extends StatelessWidget {
  final int count;
  const _OrphanWarnRow({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: scheme.semanticWarning,
          border: Border.all(
            color: scheme.outline,
            width: AppElevation.borderWidthSm,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.info,
                size: 14, color: scheme.onSurface),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '未知（原题已删除）$count 道：孤儿错题，无法归入任何分组。',
                style: AppTheme.textOf(context)
                    .labelSmall
                    ?.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
