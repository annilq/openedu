import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/presentation/shell_navigation.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/adaptive_shell.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../children/providers/children_provider.dart';
import '../../../children/presentation/screens/child_form_screen.dart';
import '../../../assistant/presentation/screens/assistant_chat_page.dart';
import '../../../export/domain/export_repository.dart';
import '../../../export/presentation/export_preview_page.dart';
import '../../../practice/presentation/screens/practice_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../review/presentation/screens/review_screen.dart';
import '../../../review/presentation/screens/wrong_questions_screen.dart';
import '../../../model_management/presentation/screens/parent_model_management_screen.dart';
import '../providers/home_notifier.dart';
import '../providers/parent_tasks_notifier.dart';
import '../providers/selected_child_provider.dart';
import '../screens/parent_task_review_screen.dart';
import '../widgets/child_home.dart';
import '../widgets/parent/parent_child_selector.dart';
import '../widgets/parent/parent_overview_view.dart';
import '../widgets/parent/parent_task_form_view.dart';
import '../widgets/parent/parent_tutor_logs_view.dart';
import '../widgets/parent/parent_question_bank_view.dart';
import '../widgets/parent/parent_tasks_view.dart';
import '../widgets/parent/parent_wrong_questions_view.dart';
import 'child_mastery_screen.dart';
import '../../../../shared/widgets/app_actions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.user, required this.onLogout});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// 家长端当前页面——导航的**唯一**事实源（ADR-0059）。
  ///
  /// 以前是三个并列状态：侧栏索引 + 审核 / 编辑覆盖层 + `_showProfile` 布尔。三者并存
  /// 就需要「谁压谁」的裁决，而裁决散在各回调里（侧栏点击记得清覆盖层、底部「我的」
  /// 忘了清 → 审核中看到的是审核页，个人信息压根没进渲染树）。合成 `sealed` 后各入口
  /// 天然互斥，且 `switch` 穷尽性由编译器保证。
  _ParentPage _parentPage = const _Overview();

  int _childNavIndex = 0;
  bool _showProfile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.user.isParent) {
        ref.read(childrenNotifierProvider.notifier).loadChildren();
      } else {
        ref.read(todayTasksNotifierProvider.notifier).load();
        ref.read(dueReviewNotifierProvider.notifier).load();
      }
    });
  }

  void _navigateToPractice(TaskModel task, {bool preview = false}) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => PracticeScreen(
          task: task,
          onDone: () {
            Navigator.of(context).pop();
            // 完成做题后统一刷新所有受影响的娃娃端数据：今日任务 / 待复习 /
            // 错题本 / 掌握度。否则回到各页仍显示做题前的旧（空）快照。
            ref.read(todayTasksNotifierProvider.notifier).load();
            ref.read(dueReviewNotifierProvider.notifier).load();
            ref.read(childWrongQuestionsProvider.notifier).load();
            ref.read(masteryNotifierProvider.notifier).load(widget.user.id);
          },
        ),
      ),
    );
  }

  /// 统一的导航出口：所有入口（侧栏 / 底部「我的」/ 侧栏头部 / 助手卡片跳转）都只
  /// 做这一件事——替换当前页面。没有第二个状态需要顺带清理。
  void _go(_ParentPage page) => setState(() => _parentPage = page);

  /// R3：生成草稿后进审核页。[back] 记下从哪儿进来，退出时回来源页而非一律回概览。
  void _navigateToReview(TaskModel draft) {
    _go(_TaskReview(draft, back: _highlightFor(_parentPage)));
  }

  void _backToHomeFromReview() {
    // 刷新家长侧概览（作废/派发后列表/进度可能变动）
    // 概览与任务页共用同一份状态，这里按「全部状态」重新拉第一页即可。
    ref
        .read(parentTasksNotifierProvider.notifier)
        .load(kAllTaskStatuses);
    final selected = ref.read(selectedChildProvider);
    if (selected != null) {
      ref.read(progressNotifierProvider.notifier).load(selected.id);
      ref.read(masteryNotifierProvider.notifier).load(selected.id);
      ref
          .read(parentWrongQuestionsProvider.notifier)
          .load(selected.id);
    }
    _go(_highlightFor(_parentPage));
  }

  /// ChildFormScreen 保存后的统一回调（创建 + 编辑共用）。
  void _onChildFormSaved(UserModel saved) {
    // 列表已在 notifier 内刷新；这里同步选中并回到首页/关闭编辑层。
    final sel = ref.read(selectedChildProvider);
    if (sel == null) {
      ref.read(selectedChildProvider.notifier).select(saved.id, saved.grade ?? 2);
    }
    _go(const _Overview());
  }

  void _onNavigateToEditChild(UserModel child) {
    _go(_EditChild(child));
  }

  /// 「我的」入口——**两个角色共用**（侧栏底部用户区 / 紧凑档底栏）。
  ///
  /// 必须按角色分派：家长端是 [_ParentPage] 的一个分支，娃娃端仍是「页签 +
  /// [_showProfile] 布尔」的二选一（见 [_buildChildView]）。⚠️ 只写家长端那份，
  /// 娃娃端点「我的」就毫无反应。守卫 `test/parent_nav_single_source_test.dart`。
  void _onProfileTap() {
    if (widget.user.isParent) {
      _go(const _Profile());
      return;
    }
    setState(() => _showProfile = true);
  }

  /// 侧栏头部「添加娃娃」。
  void _onNavigateToAddChild() => _go(const _AddChild());

  /// 切换娃娃端 Tab：改变 IndexedStack 索引，并在该页「变为可见」时重新拉取最新数据。
  ///
  /// 关键修复：娃娃端所有 Tab 被同一 [IndexedStack] 常驻挂载，[initState] 只在 App
  /// 启动那一刻跑一次（此时还没做过题 → 数据为空的旧快照）。切回 Tab 只翻转 index、
  /// 不会重跑 initState，所以必须在这里显式触发对应 provider 的 load()。
  void _switchChildTab(int index) {
    if (index == _childNavIndex) return; // 已在该页，避免重复加载
    setState(() {
      _showProfile = false;
      _childNavIndex = index;
    });
    _refreshChildTab(index);
  }

  /// 按 Tab 索引派发对应 provider 的刷新（与屏幕 initState 中的首次加载保持一致）。
  void _refreshChildTab(int index) {
    switch (index) {
      case 0: // 首页：今日任务 + 待复习
        ref.read(todayTasksNotifierProvider.notifier).load();
        ref.read(dueReviewNotifierProvider.notifier).load();
      case 1: // 复习队列
        ref.read(dueReviewNotifierProvider.notifier).load();
      case 2: // 错题本
        ref.read(childWrongQuestionsProvider.notifier).load();
      case 3: // AI 问答：会话由 AssistantNotifier 自我管理，无需全局刷新
        break;
      case 4: // 学科掌握度
        ref.read(masteryNotifierProvider.notifier).load(widget.user.id);
    }
  }

  /// 家长端主栏：把 [_parentPage] 翻成页面。`switch` 穷尽性由 `sealed` 保证——新增
  /// 页面忘记登记会编译失败，不会出现「点了没反应」。
  Widget _buildParentPage() {
    final page = _parentPage;
    return switch (page) {
      _Overview() => ParentOverviewView(
          onNavigateToReview: _navigateToReview,
          // 空态出口：概览与任务页的「去布置任务」都落到同一个目的地。
          onNavigateToCreate: () => _go(const _CreateTask()),
        ),
      // ADR-0057：生成页不再接跳转回调——收尾（含进草稿页）由本页的监听统一负责。
      _CreateTask() => const ParentTaskFormView(),
      _WrongQuestions() => const ParentWrongQuestionsView(),
      _TutorLogs() => const ParentTutorLogsView(),
      _AddChild() => ChildFormScreen(
          mode: ChildFormMode.create,
          onSaved: _onChildFormSaved,
          onBack: () => _go(const _Overview()),
        ),
      _EditChild(child: final child) => ChildFormScreen(
          mode: ChildFormMode.edit,
          child: child,
          onSaved: _onChildFormSaved,
          onBack: () => _go(const _Overview()),
        ),
      _QuestionBank() => ParentQuestionBankView(
          onNavigateToReview: _navigateToReview,
        ),
      _Models() => const ParentModelManagementScreen(),
      _TaskList() => ParentTasksView(
          onNavigateToReview: _navigateToReview,
          onNavigateToCreate: () => _go(const _CreateTask()),
        ),
      _TaskReview(task: final task) => ParentTaskReviewScreen(
          task: task,
          defaultChildId: task.childId ?? ref.watch(selectedChildProvider)?.id,
          onBackToHome: _backToHomeFromReview,
          onNavigateToPractice: (t) {
            // 仅家长显式点「查看练习」时进入。默认进只读预览，
            // 不直接进入可作答态，避免误代答/代打卡污染娃娃数据。
            _go(page.back);
            _navigateToPractice(t, preview: true);
          },
        ),
      _Profile() => ProfileScreen(user: widget.user, onLogout: widget.onLogout),
    };
  }

  /// 家长端主栏 + 常驻「出题进行中」指示条（ADR-0057 P1）。
  ///
  /// 出题的 SSE 在 [taskGenNotifierProvider]（非 autoDispose）里跑，切 Tab 不中断；
  /// 但旧实现里指示 UI 全在生成页，家长一走就看不见、回来也不知道进度。这里把进度条
  /// 挂在壳层、跨 Tab 常驻，并带一个随时可点的停止按钮（强制关闭后台生成，保留已出题）。
  Widget _buildParentBody() {
    final gen = ref.watch(taskGenNotifierProvider);
    final preview = gen is TaskGenPreview && gen.streaming ? gen : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview != null)
          _GenerationBanner(
            state: preview,
            onStop: () =>
                ref.read(taskGenNotifierProvider.notifier).stop(),
          ),
        Expanded(child: _buildParentPage()),
      ],
    );
  }

  /// 出题进行中的常驻指示条（跨 Tab），带停止按钮。
  Widget? _genTrailing(TaskGenState gen) {
    if (gen is! TaskGenPreview || !gen.streaming) return null;
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final label = gen.expected > 0
        ? '${gen.questions.length}/${gen.expected}'
        : '${gen.questions.length}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: app.accent,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: app.onAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// 娃娃端复习页的导出入口（ADR-0052）：屏幕上到期的是哪些题，纸上就是哪些题。
  ///
  /// 注入而非页内自建的原因见 [ReviewScreen.onExportDue]——按 ADR-0037，
  /// `features/review` 不得 import `features/export`，关联只能在 home 组合根建立。
  ///
  /// 请求不带 `childId`：娃娃端的作用域由服务端按调用者 token 钉死
  /// （来源 = wrong_book、娃娃 = 自己），客户端无从越过自己的错题本。
  void _exportDueReviews() {
    final state = ref.read(dueReviewNotifierProvider);
    if (state is! DueReviewLoaded || state.items.isEmpty) return;
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ExportPreviewPage(
          request: const ExportSheetRequest(
            source: 'wrong_book',
            dueOnly: true,
          ),
          title: '今日复习',
          downgradedCount: countDowngradedQuestions(
            stems: state.items.map((e) => e.stem),
            optionLists: state.items.map((e) => e.options),
          ),
        ),
      ),
    );
  }

  Widget _buildChildView() {
    if (_showProfile) {
      return ProfileScreen(user: widget.user, onLogout: widget.onLogout);
    }
    return IndexedStack(
      index: _childNavIndex,
      children: [
        ChildHome(
          user: widget.user,
          onNavigateToPractice: _navigateToPractice,
          onNavigateToReview: () => _switchChildTab(1),
          onNavigateToWrongQuestions: () => _switchChildTab(2),
          onNavigateToTutor: () => _switchChildTab(3),
        ),
        ReviewScreen(
          showBack: false,
          // 复习页是页签、不是 push 出来的路由，「返回」只能由壳翻译成切页签。
          onExit: () => _switchChildTab(0),
          onExportDue: _exportDueReviews,
        ),
        const WrongQuestionsScreen(showBack: false),
        const AssistantChatPage(showBack: false),
        ChildMasteryScreen(user: widget.user),
      ],
    );
  }

  // 家长端导航目的地：与旧 ParentSidebar 同序（0-4 + 6 题库）。
  // 审核覆盖层存在时先关层再切换（复用旧侧栏 onNavTap 行为）。
  List<AdaptiveNavDestination> _parentDestinations(
    _ParentPage page,
    TaskGenState gen,
  ) {
    // 审核页高亮「进来时的那一页」——审核是任务的延续，不是一个新的侧栏入口。
    final active = _highlightFor(page);
    return [
      AdaptiveNavDestination(
          icon: LucideIcons.layoutDashboard,
          label: '概览',
          active: active is _Overview,
          onTap: () => _go(const _Overview())),
      AdaptiveNavDestination(
          icon: LucideIcons.listTodo,
          label: '任务',
          active: active is _TaskList,
          onTap: () => _go(const _TaskList())),
      AdaptiveNavDestination(
          icon: LucideIcons.pencil,
          label: '布置任务',
          active: active is _CreateTask,
          onTap: () => _go(const _CreateTask()),
          // ADR-0057 P1：出题进行中在侧栏也亮一个进度徽标，点它即回生成页。
          trailing: _genTrailing(gen)),
      AdaptiveNavDestination(
          icon: LucideIcons.bookOpen,
          label: '错题本',
          active: active is _WrongQuestions,
          onTap: () => _go(const _WrongQuestions())),
      AdaptiveNavDestination(
          icon: LucideIcons.sparkles,
          label: 'AI 答疑记录',
          active: active is _TutorLogs,
          onTap: () => _go(const _TutorLogs())),
      AdaptiveNavDestination(
          icon: LucideIcons.library,
          label: '题库',
          active: active is _QuestionBank,
          onTap: () => _go(const _QuestionBank())),
      AdaptiveNavDestination(
          icon: LucideIcons.cpu,
          label: '模型管理',
          active: active is _Models,
          onTap: () => _go(const _Models())),
    ];
  }

  List<AdaptiveNavDestination> _childDestinations(int activeIndex) => [
    AdaptiveNavDestination(
        icon: LucideIcons.house,
        label: '首页',
        active: activeIndex == 0,
        onTap: () => _switchChildTab(0)),
    AdaptiveNavDestination(
        icon: LucideIcons.refreshCw,
        label: '复习',
        active: activeIndex == 1,
        onTap: () => _switchChildTab(1)),
    AdaptiveNavDestination(
        icon: LucideIcons.bookOpen,
        label: '错题本',
        active: activeIndex == 2,
        onTap: () => _switchChildTab(2)),
    AdaptiveNavDestination(
        icon: LucideIcons.sparkles,
        label: '问 AI 老师',
        active: activeIndex == 3,
        onTap: () => _switchChildTab(3)),
    AdaptiveNavDestination(
        icon: LucideIcons.target,
        label: '掌握度',
        active: activeIndex == 4,
        onTap: () => _switchChildTab(4)),
  ];

  /// 「我的」入口。家长端与页面共用同一个状态；娃娃端仍是页签 + 布尔两套，
  /// 所以高亮由调用方传进来（娃娃端在显示个人信息时置 -1，避免页签与「我的」
  /// 同时高亮）。
  AdaptiveNavDestination _profileDestination({required bool active}) =>
      AdaptiveNavDestination(
        icon: LucideIcons.userRound,
        label: '我的',
        active: active,
        onTap: _onProfileTap,
      );

  /// 壳目的地 → 家长端页面；娃娃端没有这些目的地（返回 null，意图被丢弃）。
  ///
  /// 这里是 [_parentDestinations] 之外**第二个**写入口（助手卡片跳转），所以映射
  /// 只此一处，不把编号散出去。
  _ParentPage? _parentPageFor(ShellDestination destination) {
    if (!widget.user.isParent) return null;
    return switch (destination) {
      ShellDestination.parentCreateTask => const _CreateTask(),
      ShellDestination.parentTaskList => const _TaskList(),
      ShellDestination.parentQuestionBank => const _QuestionBank(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // 壳外页面（push 出来的助手整页）请求的跳转：翻成页面后走 [_go]，与点侧栏
    // 是同一条路径（同一个状态，没有需要额外清理的覆盖层）。
    //
    // 无条件注册监听（不放进 `isParent` 分支）：ref.listen 的调用次数在多次 build
    // 之间必须一致，条件注册会让「角色分支变化」时的订阅数量对不上。
    ref.listen(shellNavigationProvider, (_, next) {
      if (next == null) return;
      // 先消费再执行：不清空的话下一次 rebuild 会重复触发同一次跳转。
      ref.read(shellNavigationProvider.notifier).consume();
      final page = _parentPageFor(next);
      if (page != null) _go(page);
    });

    // ADR-0057：出题的**收尾动作**放在这一层，不放生成页。
    //
    // 生成页（`ParentTaskFormView`）只在该侧栏索引挂载，家长一切走它就被卸载；
    // 而本页不会。凡是「任务结束了总得有人收尾」的事（提示、重置、刷新、进草稿页）
    // 都必须挂在生命周期更长的那一层——挂在页面里，人一走就成了无人区：
    // 成功不提示、失败静默，落库倒是照常发生。生成页只负责渲染 state。
    ref.listen(taskGenNotifierProvider, (_, next) {
      // 推迟到下一帧（沿用生成页旧实现的理由）：避免在 build 阶段同步弹 toast +
      // 跳转，导致 widget tree 在 shadcn_ui toast SlideEffect 动画中途销毁，
      // padding 计算拿到 NaN 触发 isNonNegative 断言。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next is TaskGenError) {
          AppToast.error(context, next.message);
          return;
        }
        if (next is! TaskGenSuccess) return;
        // 少题必须说清楚：逐题串行出题时某题失败会产生残缺草稿，静默当成功会让
        // 家长以为「语文没出」是系统漏了，而不是生成失败。
        if (next.isShort) {
          AppToast.error(context, next.shortMessage);
        } else {
          AppToast.show(context, '已保存草稿，共 ${next.task.questions.length} 道题');
        }
        ref.read(taskGenNotifierProvider.notifier).reset();
        final selected = ref.read(selectedChildProvider);
        if (selected != null) {
          ref.read(progressNotifierProvider.notifier).load(selected.id);
          ref.read(masteryNotifierProvider.notifier).load(selected.id);
          ref.read(parentWrongQuestionsProvider.notifier).load(selected.id);
        }
        _navigateToReview(next.task);
      });
    });

    if (widget.user.isParent) {
      // ADR-0057 P1：出题在壳这一层 watch，跨 Tab 常驻可见。
      final gen = ref.watch(taskGenNotifierProvider);
      return AdaptiveShell(
        mode: AppUserMode.parent,
        destinations: _parentDestinations(_parentPage, gen),
        profileDestination: _profileDestination(active: _parentPage is _Profile),
        sidebarTop: ParentChildSelector(
          onNavigateToAddChild: _onNavigateToAddChild,
          onNavigateToEditChild: _onNavigateToEditChild,
        ),
        sidebarBottom: AdaptiveUserBlock(
          user: widget.user,
          onProfileTap: _onProfileTap,
          subtitle: '家长账号',
        ),
        body: _buildParentBody(),
      );
    }

    return AdaptiveShell(
      mode: AppUserMode.child,
      // 显示个人信息时页签一律取消高亮：否则「复习」和「我的」会同时亮着。
      destinations: _childDestinations(_showProfile ? -1 : _childNavIndex),
      profileDestination: _profileDestination(active: _showProfile),
      sidebarBottom: AdaptiveUserBlock(
        user: widget.user,
        onProfileTap: _onProfileTap,
        subtitle: '${widget.user.grade ?? '?'}年级',
      ),
      body: _buildChildView(),
    );
  }
}

/// 出题进行中的常驻指示条（跨 Tab），带停止按钮。
///
/// 进度文案优先级：首题 STEP 前的阶段帧 > 当前题进度标签 > 兜底「生成中…」。
/// 停止 = [TaskGenNotifier.stop]：在当前题边界中断、保留已出题（ADR-0057 Q1=B）。
class _GenerationBanner extends StatelessWidget {
  final TaskGenPreview state;
  final VoidCallback onStop;

  const _GenerationBanner({required this.state, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final label = state.stage.isNotEmpty
        ? state.stage
        : state.liveLabel.isNotEmpty
            ? state.liveLabel
            : '生成中…';
    final count = state.expected > 0
        ? '已出 ${state.questions.length}/${state.expected} 题'
        : '已出 ${state.questions.length} 题';
    return Container(
      decoration: BoxDecoration(
        color: app.surfaceActive,
        border: Border(
          bottom: BorderSide(
            color: app.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.loaderCircle, size: 16, color: app.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: text.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(count,
                    style: text.labelSmall
                        ?.copyWith(color: app.onSurfaceVariant)),
              ],
            ),
          ),
          AppIconAction(
            icon: LucideIcons.x,
            semanticLabel: '停止生成',
            onPressed: onStop,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 家长端导航状态（ADR-0059）
// ---------------------------------------------------------------------------

/// 家长端页面：导航的**唯一**事实源（ADR-0059）。
///
/// 取代「索引 + 审核 / 编辑覆盖层 + `_showProfile`」三个并列状态——那套写法谁盖谁
/// 要靠每个回调自己记得清理。合成 `sealed` 后：各入口天然互斥、无需优先级裁决；
/// `_buildParentPage()` 的 `switch` 由编译器保证穷尽，漏登记会编译失败。
sealed class _ParentPage {
  const _ParentPage();
}

/// 概览。
class _Overview extends _ParentPage {
  const _Overview();
}

/// 布置任务（生成页）。
class _CreateTask extends _ParentPage {
  const _CreateTask();
}

/// 任务列表。
class _TaskList extends _ParentPage {
  const _TaskList();
}

/// 错题本。
class _WrongQuestions extends _ParentPage {
  const _WrongQuestions();
}

/// AI 答疑记录。
class _TutorLogs extends _ParentPage {
  const _TutorLogs();
}

/// 添加娃娃（ChildFormScreen 创建态）。
class _AddChild extends _ParentPage {
  const _AddChild();
}

/// 编辑娃娃资料（ChildFormScreen 编辑态）。
class _EditChild extends _ParentPage {
  final UserModel child;

  const _EditChild(this.child);
}

/// 题库。
class _QuestionBank extends _ParentPage {
  const _QuestionBank();
}

/// 模型管理。
class _Models extends _ParentPage {
  const _Models();
}

/// 草稿审核。
class _TaskReview extends _ParentPage {
  final TaskModel task;

  /// 退出审核后回到的页面——保留「从哪儿进来就回哪儿」的既有行为
  /// （从概览点进来回概览，从任务列表点进来回列表）。
  final _ParentPage back;

  const _TaskReview(this.task, {required this.back});
}

/// 个人信息（「我的」）。
class _Profile extends _ParentPage {
  const _Profile();
}

/// 侧栏高亮用的「基础页」：审核页沿用它进来的那一页的高亮。
///
/// 审核不是一个侧栏入口（否则「任务」会在用户从概览进来时错位高亮），而是某一页
/// 的延续，所以高亮取 [back]。
_ParentPage _highlightFor(_ParentPage page) =>
    page is _TaskReview ? page.back : page;
