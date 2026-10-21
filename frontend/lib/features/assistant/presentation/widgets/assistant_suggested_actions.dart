import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/domain/models/assistant_courseware_context.dart';
import '../../domain/assistant_suggested_action.dart';
import '../../providers/assistant_provider.dart';

/// 空态推荐操作目录（ADR-0072 / ADR-0089）：从服务端静态目录拉取，渲染成可点 chips。
///
/// - prompt 类：点击 `onPrompt(payload)`——普通提示，或触发出题子代理从文本自主判定
///   是否出判断题（不再有 quiz 旗标，ADR-0089）。
/// - navigate 类：点击 `onNavigate(payload)`（payload 是既有 `ShellDestination` 枚举）。
///
/// 出题类 chip 带动作键 `task_generate`，它们走 `onAction(payload, action)`：点这条
/// 就是明确要出题，服务端走动作直配，不必让模型从「再出几道」这类短句里猜业务。
/// 没有动作键的 chip 仍走 `onPrompt`。
///
/// 目录由后端按 `knowledge_point_id` 装配：无 id→全局能力；有 id→知识点目录(叠加全局)。
/// 失败 / 空 → 不渲染，避免空态反而多一块报错区。
final suggestedActionsProvider = FutureProvider.autoDispose
    .family<List<SuggestedAction>, String?>(
  (ref, kpId) => ref
      .watch(assistantRepositoryProvider)
      .suggestedActions(knowledgePointId: kpId),
);

class AssistantSuggestedActions extends ConsumerWidget {
  final AssistantCoursewareContext? coursewareContext;

  /// 给定列表模式（票 03(a)）：非空时直接渲染这组 chips，不再走 provider 拉取空态目录。
  /// 用于回复后 follow-up：服务端随 `SUGGESTED_ACTIONS` 帧下发、挂在末条 ai 消息下方。
  final List<SuggestedAction>? givenActions;

  final void Function(String payload) onPrompt;
  final void Function(String target) onNavigate;

  /// 意图已知的 chip 走这里：连文本带动作键一起发（ADR-0081 动作直配）。
  /// 可为空——不提供时带动作键的 chip 退回 [onPrompt]，只是丢掉直配这一层。
  final void Function(String payload, String action)? onAction;

  const AssistantSuggestedActions({
    super.key,
    this.coursewareContext,
    this.givenActions,
    required this.onPrompt,
    required this.onNavigate,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    final List<SuggestedAction> actions;
    if (givenActions != null) {
      // 给定列表模式：直接渲染，不拉取空态目录。
      actions = givenActions!;
    } else {
      final async =
          ref.watch(suggestedActionsProvider(coursewareContext?.knowledgePointId));
      switch (async) {
        case AsyncData(:final value) when value.isEmpty:
          return const SizedBox.shrink();
        case AsyncData(:final value):
          actions = value;
        case _:
          return const SizedBox.shrink();
      }
    }

    if (actions.isEmpty) return const SizedBox.shrink();
    return _chipsColumn(scheme, text, actions);
  }

  /// 「试试这些：」标签 + 可点 chips（空态目录与回复后 follow-up 共用）。
  Widget _chipsColumn(
    AppColors scheme,
    AppText text,
    List<SuggestedAction> actions,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl2, AppSpacing.lg, AppSpacing.xl2, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '试试这些：',
              style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final a in actions)
                  _SuggestionChip(
                    label: a.label,
                    onTap: () {
                      if (a.kind == 'navigate') {
                        onNavigate(a.payload);
                      } else if (a.action != null && onAction != null) {
                        onAction!(a.payload, a.action!);
                      } else {
                        onPrompt(a.payload);
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      );
}

/// 推荐操作 chip：新粗野描边药丸（墨黑 hairline 边 + raised 底），点击走焦点树。
class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppFocusableAction(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
        child: Text(
          label,
          style: text.labelMedium?.copyWith(color: scheme.onSurface),
        ),
      ),
    );
  }
}
