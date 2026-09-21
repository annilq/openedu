import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_scroll_page.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../providers/parent_task_review_notifier.dart';
import '../widgets/parent/parent_question_card.dart';
import '../widgets/parent/parent_task_review_action_bar.dart';
import '../widgets/parent/parent_task_review_summary.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_dialog.dart';

/// 家长草稿审核页（R-Q1=c / R-Q3 / R-Q4 / R-Q5=b）。
///
/// 入口：ParentTaskFormView 生成、家长在审阅闸门点「确认」后跳转（ADR-0056）。
/// 动作：单题/批量加入题库、删除、单题换一题、题干/选项/答案/解析
/// 内联编辑、锁定确认、派发、作废。整卷重生成已移除——它等价于整份重来，与闸门处的
/// 「重新生成」重复（ADR-0056）。
class ParentTaskReviewScreen extends ConsumerStatefulWidget {
  final TaskModel task;

  /// 派发时若创建时已经选好娃娃则直接绑定，否则弹窗选择。
  final String? defaultChildId;

  /// 返回 Home（Overview）或派发给娃娃后跳 PracticeScreen 预览。
  final VoidCallback onBackToHome;
  final void Function(TaskModel task)? onNavigateToPractice;

  const ParentTaskReviewScreen({
    super.key,
    required this.task,
    this.defaultChildId,
    required this.onBackToHome,
    this.onNavigateToPractice,
  });

  @override
  ConsumerState<ParentTaskReviewScreen> createState() =>
      _ParentTaskReviewScreenState();
}

class _ParentTaskReviewScreenState
    extends ConsumerState<ParentTaskReviewScreen> {
  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void didUpdateWidget(ParentTaskReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同一位置换成另一条任务：provider 以 taskId 为 key，新 key 拿到的是一个停在
    // Loading 的新 notifier。不在这里补取数，页面就会永远转圈。
    if (oldWidget.task.id != widget.task.id) _loadDetail();
  }

  /// 进页面补取一次完整任务——**详情数据一律以服务端为准**。
  ///
  /// 入参 `widget.task` 只是个「要打开哪条」的信封：ADR-0053 之后列表接口
  /// （`GET /tasks`）只回摘要（`question_count` + 学科，**不内嵌题目**），家长从任务
  /// 列表或概览点进来时它 `questions` 恒为空。此前页面直接拿它当 state，于是渲染出
  /// 「草稿暂未包含任何题目」，与卡片上的「N 题」当场打架——题一直在库里，只是没人取。
  ///
  /// 放 post-frame 而非 build 内：在 build 里同步改被本组件 watch 的 provider 会触发
  /// 重入重建循环（见 `shared/utils/load_once.dart` 的反模式说明）。
  void _loadDetail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .load(widget.task.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(parentTaskReviewProvider(widget.task.id));
    final app = AppTheme.colorsOf(context);
    final content = switch (state) {
      ReviewLoading() => const AppLoading(),
      ReviewError(:final message) => AppError(
          message: message,
          onRetry: () {
            ref
                .read(parentTaskReviewProvider(widget.task.id).notifier)
                .load(widget.task.id);
          },
        ),
      ReviewLoaded(
        task: final task,
        busyTqId: final busyTqId,
        liveText: final liveText,
      ) =>
        _buildBody(task, busyTqId, liveText),
    };
    return CupertinoPageScaffold(
      backgroundColor: app.surface,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: app.surface,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: widget.onBackToHome,
          child: const Icon(LucideIcons.arrowLeft, size: 22),
        ),
        middle: const Text('草稿审核'),
      ),
      // 操作栏移出导航栏，改为与正文同边距（xl2）的固定头部，
      // 统一按钮高度与风格，避免与页面内容不对齐、按钮大小参差。
      child: state is ReviewLoaded
          ? Column(
              children: [
                TaskReviewActionBar(
                  task: state.task,
                  locked: state.anyBusy,
                  defaultChildId: widget.defaultChildId,
                  onPromoteAll: _onPromoteAll,
                  onDiscard: _onDiscard,
                  onConfirm: _onConfirm,
                  onAssign: _onAssign,
                  onBackToHome: widget.onBackToHome,
                  onNavigateToPractice: widget.onNavigateToPractice,
                ),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }

  // ============ Body ============

  Widget _buildBody(
    TaskModel task,
    String? busyTqId,
    String liveText,
  ) {
    return AppScrollPage(
      children: [
        TaskReviewSummary(
          task: task,
          // 草稿态才给改卷名入口；整卷 busy 期间一并禁用（locked 由外部表达为 null）。
          onEditTitle: task.isDraft && busyTqId == null
              ? () => _onEditMeta(task)
              : null,
        ),
        const SizedBox(height: AppSpacing.xl2),
        if (task.questions.isEmpty)
          // 允许删到 0 题：整卷重生成已移除（ADR-0056），故空态只给指路文案——
          // 草稿页不能加题，删空之后只能回生成页/题库重来，或作废这份草稿。
          const _EmptyHint()
        else
          for (var i = 0; i < task.questions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: ParentQuestionCard(
                key: ValueKey(task.questions[i].id),
                index: i + 1,
                question: task.questions[i],
                isDraft: task.isDraft,
                // 进行中：按钮全禁 + spinner，杜绝连点并发。
                busy: busyTqId == task.questions[i].id,
                // 单题动作的实时文本只给当前这张卡（整卷的走顶部进度区）。
                liveText: busyTqId == task.questions[i].id ? liveText : '',
                onPromote: () => _onPromoteOne(task.id, task.questions[i].id),
                onDelete: () => _onDelete(task.id, task.questions[i].id),
                onRegenerate: () =>
                    _onRegenerateOne(task.id, task.questions[i].id),
                onEdit: (edits) =>
                    _onEdit(task.id, task.questions[i].id, edits),
              ),
            ),
      ],
    );
  }

  // ============ Actions ============

  Future<void> _onPromoteOne(String taskId, String tqId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .promoteOne(taskId: taskId, tqId: tqId);
      if (!mounted) return;
      AppToast.show(context, '已加入题库');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onPromoteAll(String taskId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .promoteAll(taskId);
      if (!mounted) return;
      AppToast.show(context, '全部加入题库成功');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onDelete(String taskId, String tqId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .removeOne(taskId: taskId, tqId: tqId);
      if (!mounted) return;
      AppToast.show(context, '已删除');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onRegenerateOne(String taskId, String tqId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .regenerateOne(taskId: taskId, tqId: tqId);
      if (!mounted) return;
      AppToast.show(context, '已生成新题目');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onEdit(
      String taskId, String tqId, Map<String, dynamic> edits) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .editOne(taskId: taskId, tqId: tqId, edits: edits);
      if (!mounted) return;
      AppToast.show(context, '题目已更新');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  /// 编辑卷名（仅草稿态）：弹窗内 ShadInput 改标题，确认后 PUT /tasks/{id}。
  Future<void> _onEditMeta(TaskModel task) async {
    final controller = TextEditingController(text: task.title);
    final newTitle = await showShadDialog<String>(
      context: context,
      builder: (ctx) {
        final app = AppTheme.colorsOf(ctx);
        return ShadDialog(
          title: const Text('编辑标题'),
          description: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text('仅草稿态可修改，锁定成卷后标题随卷固定。'),
          ),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ShadButton(
              onPressed: () {
                final t = controller.text.trim();
                if (t.isEmpty) return;
                Navigator.of(ctx).pop(t);
              },
              child: const Text('保存'),
            ),
          ],
          backgroundColor: app.surface,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: ShadInput(
              controller: controller,
              autofocus: true,
              maxLength: 255,
              placeholder: const Text('任务标题'),
            ),
          ),
        );
      },
    );
    controller.dispose();
    if (newTitle == null || newTitle == task.title) return;
    if (!mounted) return;
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .editMeta(taskId: task.id, title: newTitle);
      if (!mounted) return;
      AppToast.show(context, '标题已更新');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onConfirm(TaskModel task) async {
    try {
      final confirmed = await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .confirm(task.id);
      if (!mounted) return;
      AppToast.show(context, '已锁定成卷');
      // 若家长预选了娃娃（创建时就选好），自动下一步派发
      final childId = widget.defaultChildId ?? confirmed.childId;
      if (childId != null) {
        await _onAssign(confirmed, childId);
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onAssign(TaskModel task, String childId) async {
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .assign(taskId: task.id, childId: childId);
      if (!mounted) return;
      // 方案 A：派发后回到家长工作台，不自动跳进娃娃做题页（避免误代答/代打卡）。
      // 家长如需核对题目，可显式点「查看练习」进入代答/预览。
      AppToast.show(context, '已派发，娃娃登录后即可在「今日任务」里练习');
      widget.onBackToHome();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _onDiscard(String taskId) async {
    // 走 AppDialog.confirm：本页自己那份 `_showConfirmDialog` 是它的第三份抄写
    // （ADR-0058 Rule of Two），且当时只剩一个调用点。
    final confirmed = await AppDialog.confirm(
      context,
      title: const Text('确定作废草稿?'),
      content: const Text('作废后已加入题库的题目会一并删除，且无法恢复。'),
      confirmLabel: '作废',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(parentTaskReviewProvider(widget.task.id).notifier)
          .discard(taskId);
      if (!mounted) return;
      AppToast.show(context, '草稿已作废');
      widget.onBackToHome();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }
}


/// 草稿被删到 0 题时的空态。
///
/// 整卷重生成移除后（ADR-0056）这里**不再给按钮**：草稿页没有「添加题目」入口，
/// 删空即无法在页内补齐，给一个点不了的按钮比不给更糟。只指路：回「布置任务」或题库重来。
///
/// 走 [AppEmptyState]（ADR-0051）而非手搓色块：`tone` 给撞色底 = 强调态（带硬阴影），
/// 与原来 88 黄块 + 墨黑描边的观感一致，但文案/间距/动画都归设计系统管。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      child: AppEmptyState(
        icon: LucideIcons.inbox,
        tone: AppBrutal.yellow,
        title: '草稿暂未包含任何题目',
        message: '草稿页不能新增题目，请回「布置任务」重新生成，或到题库选题组卷；'
            '不需要这份草稿可直接作废。',
      ),
    );
  }
}

