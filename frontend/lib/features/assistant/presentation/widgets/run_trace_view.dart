import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/util/datetime_format.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/run_trace.dart';
import '../../providers/run_trace_provider.dart';
import 'assistant_hint_card.dart';

/// 运行轨迹列表（ADR-0088 ticket 02）：「一次运行 = 一行」。
///
/// 与助手页内的「历史会话」列表（`AssistantHistoryView`，气泡口径）并列：
/// 那边一行是一段会话的几轮问答，这边一行是一次 AI 运行——点开看全步骤 + 元数据。
/// 两个列表读同一张后端表，但端点与投影都不同（`/assistant/conversations` vs
/// `/ai/debug/conversations`），入口也分离（助手页内 vs 教师端侧栏）。
class AiRunTraceView extends ConsumerWidget {
  /// 点开一次运行（调用方负责翻成轨迹详情）。
  final ValueChanged<RunTraceRun> onOpenRun;

  const AiRunTraceView({super.key, required this.onOpenRun});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(runTraceListProvider);
    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // 取数失败要给出口：没有「重试」的话用户只能退出去再进来一次
      // （权限不足 / 服务不可用都落到这里，文案说清「没取到」而不猜原因）。
      error: (e, _) => AssistantHintCard(
        icon: LucideIcons.cloudOff,
        title: '运行轨迹读取失败',
        body: '$e',
        action: AppPrimaryButton(
          label: '重试',
          icon: LucideIcons.refreshCw,
          fullWidth: false,
          onPressed: () => ref.invalidate(runTraceListProvider),
        ),
      ),
      data: (runs) => runs.isEmpty
          ? const AssistantHintCard(
              icon: LucideIcons.route,
              title: '还没有 AI 运行记录',
              body: '用过出题、答疑、批改之后，每一次 AI 运行的全部步骤会留在这里。',
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                for (final run in runs)
                  _RunTraceRow(run: run, onTap: () => onOpenRun(run)),
              ],
            ),
    );
  }
}

/// 列表一行：运行名 + 元信息（类型 · 时间），非 done 状态带徽标。
///
/// 行整体可点 → 走 [AppCard] 的 onTap（内部是 `AppFocusableAction`，
/// Tab / Enter 也能打开，ADR-0045）。
class _RunTraceRow extends StatelessWidget {
  final RunTraceRun run;
  final VoidCallback onTap;

  const _RunTraceRow({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppCard.listRow(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.title.isEmpty ? '未命名运行' : run.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.xs2),
                Text(
                  _meta(run),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (_statusBadge(context, run.status) case final badge?) ...[
            const SizedBox(width: AppSpacing.sm),
            badge,
          ],
          const SizedBox(width: AppSpacing.sm),
          Icon(LucideIcons.chevronRight,
              size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  /// 元信息：类型标签 + 创建时间。时间解析不了时只留类型（不显示原始时间戳）。
  static String _meta(RunTraceRun run) {
    final time =
        run.createdAt == null ? '' : formatLocalDayMinute(run.createdAt!);
    return time.isEmpty ? runKindLabel(run.kind) : '${runKindLabel(run.kind)} · $time';
  }

  /// 非 done 的状态徽标；done 是常态，不占视觉噪音。失败 / 已拦截用语义色，
  /// 扫列表时先看到颜色再读到字。
  static Widget? _statusBadge(BuildContext context, String status) {
    final scheme = AppTheme.colorsOf(context);
    return switch (status) {
      'running' => const AppBadge(label: '进行中'),
      'error' => AppBadge(
          label: '失败',
          background: scheme.semanticError,
          foreground: scheme.semanticErrorFg,
        ),
      'blocked' => AppBadge(
          label: '已拦截',
          background: AppBrutal.yellow,
          foreground: AppBrutal.ink,
        ),
      _ => null,
    };
  }
}
