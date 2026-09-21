import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/util/datetime_format.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_select_strip.dart';
import '../../domain/conversation.dart';
import '../provider/conversation_history_provider.dart';
import 'assistant_hint_card.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';

/// 助手页内的「历史会话」视图（ADR-0048）。
///
/// 形态是**页内切模式**而非再 push 一层：助手页本身已经是 push 出来的整页
/// （ADR-0047），再叠「列表页 → 回放页」就成三层栈，输入栏逻辑也会分到两处。
/// 本组件只负责列表——点开某一段之后进「续接」还是「只读」，由调用方决定。
///
/// 列表分两段（ADR-0048 Q5(b)）：
/// - **我的对话**：可续接，点开就是继续聊；
/// - **孩子的对话**：按娃分段，**只能只读回放**。这不是 UX 取舍——家长发请求时
///   `child_id` 恒为 `None`，拿孩子的 session_id 去续接过不了后端归属校验，
///   会另建一段会话而屏幕上像续上了，顺带把孩子的消息当成家长的 prompt 历史灌进去。
class AssistantHistoryView extends ConsumerWidget {
  /// 点开某一段会话（调用方负责取回放载荷并决定进入聊天还是只读模式）。
  final ValueChanged<AssistantConversation> onOpen;

  /// 正在打开的那一段的 id（行内显示加载态；同一时刻只会有一个）。
  final String? openingId;

  /// 是否处于「多选管理」态：是则行可勾选、不可点开。
  final bool selecting;

  /// 已勾选的会话 id 集合（多选删除的来源）。
  final Set<String> selectedIds;

  /// 勾选态下点行 = 切换选中；非勾选态点行 = 打开。
  final ValueChanged<AssistantConversation> onToggleSelection;

  /// 进入多选态（列表顶部「管理」入口）。
  final VoidCallback onEnterSelecting;

  /// 勾选态下「全选 / 取消全选」：由调用方根据已选数量决定行为。
  final VoidCallback onToggleSelectAll;

  const AssistantHistoryView({
    super.key,
    required this.onOpen,
    this.openingId,
    this.selecting = false,
    this.selectedIds = const <String>{},
    required this.onToggleSelection,
    required this.onEnterSelecting,
    required this.onToggleSelectAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationHistoryProvider);
    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // 取数失败要给出口：没有「重试」的话用户只能退出去再进来一次。
      error: (e, _) => AssistantHintCard(
        icon: LucideIcons.cloudOff,
        title: '会话记录没取到',
        body: '$e',
        action: AppPrimaryButton(
          label: '重试',
          icon: LucideIcons.refreshCw,
          fullWidth: false,
          onPressed: () => ref.invalidate(conversationHistoryProvider),
        ),
      ),
      data: (all) => all.isEmpty
          ? const AssistantHintCard(
              icon: LucideIcons.history,
              title: '还没有历史对话',
              body: '问过的问题会留在这里，随时能翻回来接着聊。',
            )
          : _ConversationGroups(
              all: all,
              onOpen: onOpen,
              openingId: openingId,
              selecting: selecting,
              selectedIds: selectedIds,
              onToggleSelection: onToggleSelection,
              onEnterSelecting: onEnterSelecting,
              onToggleSelectAll: onToggleSelectAll,
            ),
    );
  }
}

/// 两段式分组的容器：先「我的对话」，再按娃分段的「孩子的对话」。
///
/// 顶部还放一条「多选 / 已选 N 项 / 全选」操作条（[AppSelectStrip]）——多选入口与
/// 全选放在这里而非顶栏，是因为 [AppTopBar] 的 trailing 槽位只有 40px、只够放一个
/// 图标动作（ADR-0045/0046 的顶栏几何），而这里是一整条可用宽度，能并排放多选 / 全选。
class _ConversationGroups extends StatelessWidget {
  final List<AssistantConversation> all;
  final ValueChanged<AssistantConversation> onOpen;
  final String? openingId;
  final bool selecting;
  final Set<String> selectedIds;
  final ValueChanged<AssistantConversation> onToggleSelection;
  final VoidCallback onEnterSelecting;
  final VoidCallback onToggleSelectAll;

  const _ConversationGroups({
    required this.all,
    required this.onOpen,
    this.openingId,
    this.selecting = false,
    this.selectedIds = const <String>{},
    required this.onToggleSelection,
    required this.onEnterSelecting,
    required this.onToggleSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final mine = <AssistantConversation>[];
    // 后端已按最近活动倒序，故「某娃第一次出现」的先后 = 该娃最近一段的先后：
    // 组序由这一趟扫描自然得出，零额外查询、且是确定性的。
    final kidOrder = <String>[];
    final kidItems = <String, List<AssistantConversation>>{};
    final kidNames = <String, String>{};

    for (final conv in all) {
      final childId = conv.childId;
      if (childId == null) {
        mine.add(conv);
        continue;
      }
      if (!kidItems.containsKey(childId)) {
        kidOrder.add(childId);
        kidItems[childId] = <AssistantConversation>[];
        kidNames[childId] = conv.childName ?? '孩子';
      }
      kidItems[childId]!.add(conv);
    }

    return Column(
      children: [
        AppSelectStrip(
          selecting: selecting,
          selectedCount: selectedIds.length,
          totalCount: all.length,
          onEnterSelecting: onEnterSelecting,
          onToggleSelectAll: onToggleSelectAll,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (mine.isNotEmpty)
                ..._section(context, '我的对话', mine, readOnly: false),
              for (final childId in kidOrder)
                ..._section(
                  context,
                  '${kidNames[childId]}的对话',
                  kidItems[childId]!,
                  readOnly: true,
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<AssistantConversation> items, {
    required bool readOnly,
  }) => [
    Padding(
      padding: const EdgeInsets.only(
          left: AppSpacing.xs, top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        title,
        style: AppTheme.textOf(context).labelLarge?.copyWith(
              color: AppTheme.colorsOf(context).onSurfaceVariant,
            ),
      ),
    ),
    for (final conv in items)
      _ConversationRow(
        conversation: conv,
        readOnly: readOnly,
        opening: openingId == conv.id,
        selecting: selecting,
        selected: selectedIds.contains(conv.id),
        onTap: selecting
            ? () => onToggleSelection(conv)
            : () => onOpen(conv),
      ),
  ];
}

/// 列表一行：会话名 + 元信息（几轮 · 最近活动时间），孩子的条目带「只读」徽标。
///
/// 用 [AppCard.listRow] 而非标准卡：密集列表逐行套 2px 边 + 硬阴影会让整页过载
/// （ADR-0044「列表降噪」）。行整体可点 → 走 [AppCard] 的 onTap（内部是
/// `AppFocusableAction`，所以 Tab / Enter 也能打开，ADR-0045）。
///
/// 多选态下左侧出现勾选标记，整行底色切到选中色（[AppColors.surfaceActive]），
/// 点行 = 切换选中（不打开）。
class _ConversationRow extends StatelessWidget {
  final AssistantConversation conversation;
  final bool readOnly;
  final bool opening;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;

  const _ConversationRow({
    required this.conversation,
    required this.readOnly,
    required this.opening,
    this.selecting = false,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final canTap = !opening;
    return AppCard.listRow(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      // 选中底色：多选态下选中行切到 surfaceActive（ADR-0046 选中语言）。
      color: selecting && selected ? scheme.surfaceActive : null,
      onTap: canTap ? onTap : null,
      child: Row(
        children: [
          if (selecting) ...[
            Icon(
              selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.xs2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _meta(conversation),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    if (readOnly) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const AppBadge(label: '只读'),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (opening)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            )
          else if (!selecting)
            Icon(LucideIcons.chevronRight,
                size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  /// 元信息：几轮 + 最近活动时间。两项都可能缺（时间解析不了 / 一条气泡都没有），
  /// 所以拼接而不是硬套模板串。
  static String _meta(AssistantConversation c) {
    final parts = <String>[];
    if (c.roundCount > 0) parts.add('${c.roundCount} 轮');
    final time = c.updatedAt == null ? '' : formatLocalDayMinute(c.updatedAt!);
    if (time.isNotEmpty) parts.add(time);
    return parts.join(' · ');
  }
}
