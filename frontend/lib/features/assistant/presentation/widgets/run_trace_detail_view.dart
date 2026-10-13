import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/run_trace.dart';
import '../../providers/run_trace_provider.dart';
import 'assistant_hint_card.dart';

/// 运行轨迹详情（ADR-0088 ticket 02）：一次 AI 运行的**全步骤 + 元数据**。
///
/// 这是与历史会话气泡**并列的第二个消费者**：气泡投影把 `routing`/`tool_*` 剥掉
/// 只留问答；本页恰恰渲染它们，并带上每步的 model / token / 延迟——审计与排障
/// 视角。「哪一步最费 token / 最慢 / 被拦」在这里一眼看到，而不用去翻数据库。
///
/// 步级 usage / latency / model 由 ticket 01 落库；01 之前的老运行这些列为空，
/// 对应位置显示占位（「token 未记录」等）而不是崩、也不是误导性的 0。
class AiRunTraceDetailView extends ConsumerWidget {
  final String runId;
  final VoidCallback onBack;

  const AiRunTraceDetailView({
    super.key,
    required this.runId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(runTraceDetailProvider(runId));
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: Row(
            children: [
              AppIconAction(
                icon: LucideIcons.chevronLeft,
                semanticLabel: '返回',
                onPressed: onBack,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text('运行详情', style: text.titleLarge)),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            // 越权（403）/ 服务不可用都落到这里：说清「没取到」并给重试，
            // 不猜原因、不白屏。
            error: (e, _) => AssistantHintCard(
              icon: LucideIcons.cloudOff,
              title: '运行轨迹读取失败',
              body: '$e',
              action: AppPrimaryButton(
                label: '重试',
                icon: LucideIcons.refreshCw,
                fullWidth: false,
                onPressed: () =>
                    ref.invalidate(runTraceDetailProvider(runId)),
              ),
            ),
            data: (detail) => detail.steps.isEmpty
                ? const AssistantHintCard(
                    icon: LucideIcons.route,
                    title: '这次运行没有留下步骤',
                    body: '可能是运行刚发起还没落库，稍后回来看看。',
                  )
                : _TraceBody(detail: detail),
          ),
        ),
      ],
    );
  }
}

/// 概要卡 + 全步骤列表。
class _TraceBody extends StatelessWidget {
  final RunTraceDetail detail;

  const _TraceBody({required this.detail});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      children: [
        _RunSummaryCard(detail: detail),
        const SizedBox(height: AppSpacing.md),
        for (final step in detail.steps) _StepCard(step: step),
      ],
    );
  }
}

/// 概要卡：运行名 + 类型 / 状态 + 会话级合计。
///
/// 合计**由步级上推**（ADR-0088 §2.5：不建会话级汇总列，`GROUP BY conversation_id`
/// 在后端随时可算；前端同理，步级数据已经在手上）。没有任何一步带 usage 时显示
/// 「token 未记录」而不是 0——0 是「跑了但没花 token」，与「没记录」是两件事。
class _RunSummaryCard extends StatelessWidget {
  final RunTraceDetail detail;

  const _RunSummaryCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final run = detail.run;
    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            run.title.isEmpty ? '未命名运行' : run.title,
            style: text.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.xs2),
          Text(
            _subtitle(run),
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _totals(detail.steps),
            style: text.labelMedium?.copyWith(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }

  static String _subtitle(RunTraceRun run) {
    final parts = [runKindLabel(run.kind), _statusLabel(run.status)];
    if (run.model != null && run.model!.isNotEmpty) {
      parts.add(run.model!);
    }
    return parts.join(' · ');
  }

  static String _totals(List<RunTraceStep> steps) {
    final hasUsage = steps.any((s) => s.usage != null);
    final hasLatency = steps.any((s) => s.latencyMs != null);
    final tokens = steps.fold<int>(0, (sum, s) => sum + (s.usage?.total ?? 0));
    final ms = steps.fold<int>(0, (sum, s) => sum + (s.latencyMs ?? 0));
    final tokenPart = hasUsage ? '$tokens token' : 'token 未记录';
    final msPart = hasLatency ? '$ms ms' : '耗时未记录';
    return '$tokenPart · $msPart';
  }
}

/// 一步：步骤徽标 + 角色 + 内容 + 步级元数据（model / token / 延迟）。
class _StepCard extends StatelessWidget {
  final RunTraceStep step;

  const _StepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppCard(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge(label: step.step),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _roleLabel(step.role),
                style: text.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              // 安全标记属「默认可见的元数据」（ADR-0088 §2.4）：被拦的步骤要能
              // 一眼认出；内容脱敏与破窗留痕归 ticket 03，不在这里展开。
              if (step.blocked) ...[
                const SizedBox(width: AppSpacing.xs),
                AppBadge(
                  label: '已拦截',
                  background: AppBrutal.yellow,
                  foreground: AppBrutal.ink,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            step.content,
            style: text.bodyMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.xs2),
          Text(
            _meta(step),
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 步级元数据：模型 · token · 延迟。缺列显示占位——「没记录」与「0」必须分开。
  static String _meta(RunTraceStep step) {
    final model = (step.model != null && step.model!.isNotEmpty)
        ? step.model!
        : '模型未记录';
    final usage = step.usage == null ? 'token 未记录' : '${step.usage!.total} token';
    final latency =
        step.latencyMs == null ? '延迟未记录' : '${step.latencyMs} ms';
    return '$model · $usage · $latency';
  }

  static String _roleLabel(String role) => switch (role) {
        'user' => '用户',
        'assistant' => '助手',
        'tool' => '工具',
        'system' => '系统',
        final other => other.isEmpty ? '未知' : other,
      };
}

/// 状态 → 教师口径标签（与轨迹列表的徽标同一词汇，认不出的原样显示）。
String _statusLabel(String status) => switch (status) {
      'running' => '进行中',
      'done' => '已完成',
      'error' => '失败',
      'blocked' => '已拦截',
      final other => other.isEmpty ? '状态未知' : other,
    };
