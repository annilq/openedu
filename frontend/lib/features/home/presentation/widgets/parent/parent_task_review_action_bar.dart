import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_content_frame.dart';
import '../../../../../shared/widgets/app_toast.dart';

/// 草稿审核的顶部操作栏：随任务状态换一套出口。
///
/// 与正文同边距（xl2）的固定头部，统一按钮高度与风格，避免与页面内容不对齐、
/// 按钮大小参差。原来挤在 `parent_task_review_screen` 里占 94 行——它是「一个区块
/// 自己的操作条」（ADR-0058 §4 的 Section），不是 Page 的排版细节。
///
/// 所有动作以回调出去：本区块不认识 provider，也不认识「派发之后要跳哪」。
class TaskReviewActionBar extends StatelessWidget {
  final TaskModel task;

  /// 某题正在执行单题动作：整卷级操作一并禁用。
  final bool locked;

  /// 当前选中的娃娃。null 时派发按钮仍在，但点了提示先去首页选娃娃。
  final String? defaultChildId;

  final void Function(String taskId) onPromoteAll;
  final void Function(String taskId) onDiscard;
  final void Function(TaskModel task) onConfirm;
  final void Function(TaskModel task, String childId) onAssign;

  /// 跳练习页。宿主没给（娃娃端无此入口）时按钮禁用而非隐藏——
  /// 消失的按钮会让人以为操作丢了。
  final void Function(TaskModel task)? onNavigateToPractice;

  final VoidCallback onBackToHome;

  const TaskReviewActionBar({
    super.key,
    required this.task,
    required this.locked,
    required this.defaultChildId,
    required this.onPromoteAll,
    required this.onDiscard,
    required this.onConfirm,
    required this.onAssign,
    required this.onBackToHome,
    this.onNavigateToPractice,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: app.surface,
        border: Border(
          // 头部分隔 = 2px 墨黑描边（ADR-0044）。
          bottom: BorderSide(
              color: AppBrutal.ink, width: AppElevation.borderWidth),
        ),
      ),
      child: AppContentFrame(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.end,
            children: _buttons(context),
          ),
        ),
      ),
    );
  }

  /// 主操作用实心 primary，次操作描边，作废用 destructive。
  List<Widget> _buttons(BuildContext context) {
    if (task.isDraft) {
      // 「整卷重生成」已移除（ADR-0056）：它等价于「这份推翻重来」，与生成页审阅闸门处的
      // 「重新生成」重复，且要全量重跑。草稿页只保留逐题精修（含单题「换一题」）。
      return [
        ShadButton.outline(
          onPressed: locked || task.promotedCount == task.questions.length
              ? null
              : () => onPromoteAll(task.id),
          leading: const Icon(LucideIcons.database, size: 16),
          child: Text(
              '一键加入题库 (${task.promotedCount}/${task.questions.length})'),
        ),
        ShadButton.destructive(
          onPressed: locked ? null : () => onDiscard(task.id),
          leading: const Icon(LucideIcons.trash2, size: 16),
          child: const Text('作废'),
        ),
        ShadButton(
          onPressed: locked || task.questions.isEmpty
              ? null
              : () => onConfirm(task),
          leading: const Icon(LucideIcons.lock, size: 18),
          child: const Text('锁定并派发'),
        ),
      ];
    }
    if (task.isReady) {
      return [
        ShadButton(
          onPressed: locked
              ? null
              : defaultChildId != null
                  ? () => onAssign(task, defaultChildId!)
                  : () {
                      AppToast.show(context, '请在首页选择娃娃后再派发');
                    },
          leading: const Icon(LucideIcons.send, size: 18),
          child: Text(defaultChildId != null ? '派发任务' : '派发'),
        ),
      ];
    }
    if (task.isAssigned) {
      return [
        ShadButton.secondary(
          onPressed: onNavigateToPractice == null
              ? null
              : () => onNavigateToPractice!(task),
          leading: const Icon(LucideIcons.eye, size: 18),
          child: const Text('查看练习'),
        ),
      ];
    }
    return [
      ShadButton.secondary(
        onPressed: onBackToHome,
        child: const Text('返回首页'),
      ),
    ];
  }
}
