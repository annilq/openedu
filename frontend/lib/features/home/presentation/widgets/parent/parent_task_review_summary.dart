import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_card.dart';

/// 草稿审核的卷宗摘要：标题 + 状态 + 读数（题目数 / 已入题库）+ 出题规格。
///
/// 原是 `parent_task_review_screen` 里一个 91 行的私有方法——ADR-0058 §4：
/// 「一个区块：自己的筛选 / 列表 / 操作条」应自成一个 Section，不是 Page 里的
/// `_buildXxx`。本区块只消费一个 [TaskModel]，改动经回调出去，不认识 provider。
class TaskReviewSummary extends StatelessWidget {
  final TaskModel task;

  /// 改卷名入口。null = 不画（非草稿态标题已随卷固定，或整卷 busy 期间禁用）。
  final VoidCallback? onEditTitle;

  const TaskReviewSummary({super.key, required this.task, this.onEditTitle});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final total = task.questions.length;
    final promoted = task.promotedCount;
    final statusChip = switch (task.status) {
      'draft' => ('草稿', app.tertiary, app.onTertiary),
      'ready' => ('已锁定', app.primary, app.onPrimary),
      'assigned' => ('已派发', app.secondary, app.onSecondary),
      'done' => ('已完成', app.onSurface, app.surface),
      _ => ('未知', app.surfaceSunken, app.onSurface),
    };
    final editTitle = onEditTitle;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: AppTheme.textOf(context).headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              // 草稿态允许改卷名：生成一次要等 LLM，标题打错就作废重来代价太大。
              // 锁定（ready）后标题随卷固定，入口消失。整卷 busy 期间一并禁用。
              if (editTitle != null) ...[
                const SizedBox(width: AppSpacing.sm),
                AppIconAction(
                  icon: LucideIcons.pencil,
                  semanticLabel: '编辑标题',
                  onPressed: editTitle,
                ),
              ],
              const SizedBox(width: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: statusChip.$2,
                  borderRadius: BorderRadius.circular(AppRadius.bubble),
                  // 状态 chip = 实心色块 + 2px 墨黑描边（ADR-0044）。
                  border: Border.all(
                      color: AppBrutal.ink, width: AppElevation.borderWidth),
                ),
                child: Text(
                  statusChip.$1,
                  style: AppTheme.textOf(context).labelMedium?.copyWith(
                        color: statusChip.$3,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // 统计行与规格行刻意分离：数字统计（题目数/已入题库）是一行紧凑的
          // 「读数」，出题规格是可任意增长的 chip 集合——两者高度、增长方式都
          // 不同，混在同一个 Wrap 里时规格一多就会把统计行挤成两截、左对齐线
          // 断裂（且曾经为此给规格块压 45% 宽度上限，治标不治本）。
          Wrap(
            spacing: AppSpacing.xl2,
            runSpacing: AppSpacing.sm,
            children: [
              _Stat(
                label: '题目数',
                value: total.toString(),
                icon: LucideIcons.fileQuestion,
              ),
              _Stat(
                label: '已入题库',
                value: '$promoted / $total',
                icon: LucideIcons.database,
                tone: promoted == total ? app.primary : app.onSurfaceVariant,
              ),
            ],
          ),
          if (task.specs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _SpecsSummary(specs: task.specs),
          ],
        ],
      ),
    );
  }
}

/// 一个读数：图标 + 数值 + 名字。数值是主角（加粗 onSurface），名字是注解。
class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? tone;

  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final color = tone ?? app.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$value  ',
                style: AppTheme.textOf(context).titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: app.onSurface,
                    ),
              ),
              TextSpan(
                text: label,
                style: AppTheme.textOf(context)
                    .bodySmall
                    ?.copyWith(color: app.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 出题规格：小标题 + 通栏 chip 流。
///
/// chips 拿满卡宽后任意数量都能自然换行，不再需要「压 45% 宽度」这类
/// 与可用宽度耦合的补丁。
class _SpecsSummary extends StatelessWidget {
  final List<TaskSpecModel> specs;

  const _SpecsSummary({required this.specs});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.listChecks, size: 16, color: app.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '出题规格',
              style: AppTheme.textOf(context).labelMedium?.copyWith(
                    color: app.onSurfaceVariant,
                    letterSpacing: 0.2,
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: specs.map((s) {
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: app.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                // 小信息 chip = 1.5px 墨黑描边（ADR-0044，与学科 chip 同宽）。
                border: Border.all(
                    color: AppBrutal.ink,
                    width: AppElevation.borderWidthSm),
              ),
              child: Text(
                '${s.subject}·${s.grade}·${s.knowledgePoint} x${s.count}',
                style: AppTheme.textOf(context).bodySmall,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
