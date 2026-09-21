import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_content_frame.dart';
import '../../../../shared/widgets/app_scroll_page.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../providers/parent_task_review_notifier.dart';
import '../widgets/parent/parent_question_card.dart';

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
                _buildActionBar(state.task, app, state.anyBusy),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }

  // ============ 顶部操作栏 ============

  /// 顶部操作栏：与正文同边距（xl2）的固定头部，统一所有按钮高度（40），
  /// 主操作（锁定并派发 / 派发）用实心 primary，次操作描边，作废用 destructive。
  /// [locked] 为 true 表示某题正在执行单题动作，整卷级操作一并禁用。
  Widget _buildActionBar(TaskModel task, AppColors app, bool locked) {
    final buttons = <Widget>[];
    if (task.isDraft) {
      // 「整卷重生成」已移除（ADR-0056）：它等价于「这份推翻重来」，与生成页审阅闸门处的
      // 「重新生成」重复，且要全量重跑。草稿页只保留逐题精修（含单题「换一题」）。
      buttons.add(
        ShadButton.outline(
          
          onPressed: locked || task.promotedCount == task.questions.length
              ? null
              : () => _onPromoteAll(task.id),
          leading: const Icon(LucideIcons.database, size: 16),
          child: Text('一键加入题库 '
              '(${task.promotedCount}/${task.questions.length})'),
        ),
      );
      buttons.add(
        ShadButton.destructive(
          
          onPressed: locked ? null : () => _onDiscard(task.id),
          leading: const Icon(LucideIcons.trash2, size: 16),
          child: const Text('作废'),
        ),
      );
      buttons.add(
        ShadButton(
          
          onPressed: locked || task.questions.isEmpty
              ? null
              : () => _onConfirm(task),
          leading: const Icon(LucideIcons.lock, size: 18),
          child: const Text('锁定并派发'),
        ),
      );
    } else if (task.isReady) {
      buttons.add(
        ShadButton(
          
          onPressed: locked
              ? null
              : widget.defaultChildId != null
                  ? () => _onAssign(task, widget.defaultChildId!)
                  : () {
                      AppToast.show(context, '请在首页选择娃娃后再派发');
                    },
          leading: const Icon(LucideIcons.send, size: 18),
          child: Text(widget.defaultChildId != null ? '派发任务' : '派发'),
        ),
      );
    } else if (task.isAssigned) {
      buttons.add(
        ShadButton.secondary(
          
          onPressed: widget.onNavigateToPractice == null
              ? null
              : () => widget.onNavigateToPractice!(task),
          leading: const Icon(LucideIcons.eye, size: 18),
          child: const Text('查看练习'),
        ),
      );
    } else {
      buttons.add(
        ShadButton.secondary(
          
          onPressed: widget.onBackToHome,
          child: const Text('返回首页'),
        ),
      );
    }

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
            children: buttons,
          ),
        ),
      ),
    );
  }

  // ============ Body ============

  Widget _buildBody(
    TaskModel task,
    String? busyTqId,
    String liveText,
  ) {
    final app = AppTheme.colorsOf(context);
    final total = task.questions.length;
    final promoted = task.promotedCount;
    return AppScrollPage(
      children: [
        _buildSummary(task, app, promoted, total,
            locked: busyTqId != null),
        const SizedBox(height: AppSpacing.xl2),
        if (task.questions.isEmpty)
          // 允许删到 0 题：整卷重生成已移除（ADR-0056），故空态只给指路文案——
          // 草稿页不能加题，删空之后只能回生成页/题库重来，或作废这份草稿。
          const _EmptyHint()
        else
          ...List.generate(task.questions.length, (i) {
            final q = task.questions[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: ParentQuestionCard(
                key: ValueKey(q.id),
                index: i + 1,
                question: q,
                isDraft: task.isDraft,
                // 进行中：按钮全禁 + spinner，杜绝连点并发。
                busy: busyTqId == q.id,
                // 单题动作的实时文本只给当前这张卡（整卷的走顶部进度区）。
                liveText: busyTqId == q.id ? liveText : '',
                onPromote: () => _onPromoteOne(task.id, q.id),
                onDelete: () => _onDelete(task.id, q.id),
                onRegenerate: () => _onRegenerateOne(task.id, q.id),
                onEdit: (edits) => _onEdit(task.id, q.id, edits),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSummary(
    TaskModel task,
    dynamic app,
    int promoted,
    int total, {
    bool locked = false,
  }) {
    final statusChip = switch (task.status) {
      'draft' => ('草稿', app.tertiary, app.onTertiary),
      'ready' => ('已锁定', app.primary, app.onPrimary),
      'assigned' => ('已派发', app.secondary, app.onSecondary),
      'done' => ('已完成', app.onSurface, app.surface),
      _ => ('未知', app.surfaceSunken, app.onSurface),
    } as (String, Color, Color);

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
              if (task.isDraft) ...[
                const SizedBox(width: AppSpacing.sm),
                AppIconAction(
                  icon: LucideIcons.pencil,
                  semanticLabel: '编辑标题',
                  onPressed: locked ? null : () => _onEditMeta(task),
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
    final confirmed = await _showConfirmDialog(
      context: context,
      title: '确定作废草稿?',
      desc: '作废后已加入题库的题目会一并删除，且无法恢复。',
      confirmText: '作废',
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

class _SpecsSummary extends StatelessWidget {
  final List<TaskSpecModel> specs;
  const _SpecsSummary({required this.specs});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    // 独立成块：小标签 + 通栏 chip 流。chips 拿满卡宽后任意数量都能自然换行，
    // 不再需要「压 45% 宽度」这类与可用宽度耦合的补丁。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.listChecks,
                size: 16, color: app.onSurfaceVariant),
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

// ============ Confirm Dialog ============

Future<bool?> _showConfirmDialog({
  required BuildContext context,
  required String title,
  required String desc,
  String confirmText = '确定',
  bool destructive = false,
}) async {
  return showShadDialog<bool>(
    context: context,
    builder: (ctx) {
      final app = AppTheme.colorsOf(ctx);
      return ShadDialog.alert(
        title: Text(title),
        description: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(desc),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          if (destructive)
            ShadButton.destructive(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmText),
            )
          else
            ShadButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmText),
            ),
        ],
        backgroundColor: app.surface,
      );
    },
  );
}
