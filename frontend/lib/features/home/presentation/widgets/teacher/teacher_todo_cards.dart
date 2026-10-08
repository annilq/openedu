import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/task.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_card.dart';

/// 教师工作台待办卡片（ticket 20）：待审核 / 待派发 / 谁没交 三条入口。
///
/// 三卡并排、点哪张进对应任务列表 Tab。计数来自 [TeacherTodoSummary]（服务端聚合），
/// 不在此处统计，避免只数已加载分页的徽标陷阱（ADR-0053）。
class TeacherTodoCards extends StatelessWidget {
  final TeacherTodoSummary summary;
  final void Function(int tab) onOpenList;

  const TeacherTodoCards({
    super.key,
    required this.summary,
    required this.onOpenList,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _TodoItem(
        icon: LucideIcons.clipboardCheck,
        label: '待审核',
        count: summary.pendingReview,
        tab: 0,
      ),
      _TodoItem(
        icon: LucideIcons.send,
        label: '待派发',
        count: summary.pendingDispatch,
        tab: 0,
      ),
      _TodoItem(
        icon: LucideIcons.userX,
        label: '谁没交',
        count: summary.notSubmitted,
        tab: 1,
      ),
    ];
    // 三卡内容等高（icon/计数/标签各一行）；Row(stretch) 必须包 IntrinsicHeight，
    // 否则落入无界高度上下文会崩（ADR-0044，stretch_row_guard 守着）。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _TodoCard(item: items[i], onOpenList: onOpenList),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodoItem {
  final IconData icon;
  final String label;
  final int count;
  final int tab;
  const _TodoItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.tab,
  });
}

class _TodoCard extends StatelessWidget {
  final _TodoItem item;
  final void Function(int tab) onOpenList;

  const _TodoCard({required this.item, required this.onOpenList});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final dim = item.count == 0;
    return AppCard(
      onTap: () => onOpenList(item.tab),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 18,
            color: dim ? app.onSurfaceVariant : app.accent,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${item.count}',
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: dim ? app.onSurfaceVariant : app.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: text.labelSmall?.copyWith(color: app.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
