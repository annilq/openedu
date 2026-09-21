import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/assistant_card.dart';

/// 卡片**类别色**：按语义族归并，而不是「一种卡片一个色」。
///
/// 为什么归并：`.impeccable.md` §Design Principles 2 要求**单屏色相 ≤ 3**，
/// 而会话回放（ADR-0048）里同一屏会连续出现多种卡片——9 种 kind 各配一色必然越限。
///
/// | 族 | kind | 色 |
/// |---|---|---|
/// | 待办 / 复习（要做的事） | `taskList` · `dueReviewList` · `guide` | `cyan` |
/// | 错题 / 掌握（要看的问题） | `wrongQuestionList` · `masteryList` · `questionBankList` | `magenta` |
/// | 结构 / 对话（无行动压力） | `question` · `progress` · `notice` · `childList` · 未登记 | 中性灰 |
///
/// `guide` 归「待办」族：它是**要用户去做一件事**的卡（去布置任务），
/// 与任务列表同一语义，不该长得像一条中性说明。
///
/// 两个族色都是**亮块**，前景一律由 [AppBrutal.onColor] 判成墨黑——不得手写黑/白。
/// 返回 `null` 表示走中性底座（`surfaceSunken` + `onSurfaceVariant`）。
Color? familyFillOf(String kind) => switch (kind) {
      AssistantCardKind.taskList ||
      AssistantCardKind.dueReviewList ||
      AssistantCardKind.guide =>
        AppBrutal.cyan,
      AssistantCardKind.wrongQuestionList ||
      AssistantCardKind.masteryList ||
      AssistantCardKind.questionBankList =>
        AppBrutal.magenta,
      _ => null,
    };

/// 卡头的类别图标：9 种卡片若共用同一个图标，会话回放里就**分不出是哪张卡**。
IconData cardIconOf(String kind) => switch (kind) {
      AssistantCardKind.question => LucideIcons.sparkles,
      AssistantCardKind.taskList => LucideIcons.listChecks,
      AssistantCardKind.wrongQuestionList => LucideIcons.bookOpen,
      AssistantCardKind.dueReviewList => LucideIcons.calendarClock,
      AssistantCardKind.masteryList => LucideIcons.target,
      AssistantCardKind.childList => LucideIcons.user,
      AssistantCardKind.progress => LucideIcons.barChart3,
      AssistantCardKind.questionBankList => LucideIcons.library,
      AssistantCardKind.guide => LucideIcons.cornerDownRight,
      _ => LucideIcons.info,
    };

/// 卡头：类别色图标底座 + 标题 +（右对齐的）归属。
///
/// 图标与底座色**都由 [kind] 推出**（[cardIconOf] / [familyFillOf]），不另收
/// `icon` 入参——调用点手上已经有 kind，再传一个图标只是多一处可能与 kind 漂移的
/// 取值。未传 kind 或属结构族时退化为中性灰底座——与收敛前那个裸 15px 灰图标
/// 同强度，不额外抢眼。
class AssistantCardHeader extends StatelessWidget {
  final String title;
  final String subject;
  final String kind;

  const AssistantCardHeader({
    super.key,
    required this.title,
    this.subject = '',
    this.kind = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final fill = familyFillOf(kind);
    return Row(
      children: [
        // 图标底座 32×32 + 1.5px 墨黑描边，规格取自 `parent_question_card` 的题号徽标
        // （密集小色块档 [AppElevation.borderWidthSm]）。
        //
        // 收敛前是一个 15px 的裸灰图标：9 种卡片在会话回放里长得一模一样，5 种列表卡
        // 又共用同一个版式，用户分不出「这是到期复习还是错题列表」。
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: fill ?? scheme.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppBrutal.ink,
              width: AppElevation.borderWidthSm,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            cardIconOf(kind),
            size: 17,
            color: fill == null ? scheme.onSurfaceVariant : AppBrutal.onColor(fill),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        if (subject.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}
