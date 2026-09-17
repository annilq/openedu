import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/adaptive_shell.dart';
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

class HomeScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.user, required this.onLogout});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _parentNavIndex = 0;
  int _childNavIndex = 0;
  bool _showProfile = false;

  /// 草稿审核覆盖层：非 null 时覆盖侧栏导航展示 ParentTaskReviewScreen。
  TaskModel? _reviewingTask;

  /// 编辑娃娃资料覆盖层（WF-5）：非 null 时展示 ChildFormScreen(edit)。
  UserModel? _editingChild;

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

  /// R3：生成草稿后跳审核页（非娃娃的「今日练习」）。
  void _navigateToReview(TaskModel draft) {
    setState(() => _reviewingTask = draft);
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
    setState(() => _reviewingTask = null);
  }

  void _onParentNavTap(int index) {
    setState(() {
      _showProfile = false;
      _parentNavIndex = index;
    });
  }

  void _onProfileTap() {
    setState(() {
      _showProfile = true;
      _editingChild = null;
    });
  }

  void _onNavigateToAddChild() {
    setState(() {
      _showProfile = false;
      _editingChild = null;
      _parentNavIndex = 5;
    });
  }

  /// ChildFormScreen 保存后的统一回调（创建 + 编辑共用）。
  void _onChildFormSaved(UserModel saved) {
    // 列表已在 notifier 内刷新；这里同步选中并回到首页/关闭编辑层。
    final sel = ref.read(selectedChildProvider);
    if (sel == null) {
      ref.read(selectedChildProvider.notifier).select(saved.id, saved.grade ?? 2);
    }
    setState(() {
      _showProfile = false;
      _editingChild = null;
      _parentNavIndex = 0;
    });
  }

  void _onNavigateToEditChild(UserModel child) {
    // 关闭选择器弹层由调用方处理；此处直接打开编辑覆盖层。
    setState(() {
      _showProfile = false;
      _editingChild = child;
    });
  }

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

  /// 家长端「详情」面板（master-detail 的 detail，ADR-0045）。返回 null 表示无详情。
  ///
  /// 大屏下它与 body 并排；中屏 / 紧凑下由 [AdaptiveShell] 整幅顶替 body——两种情况
  /// 都只需如实返回「当前该看的详情」，宽度判定交给壳，这里不做任何测量。
  ///
  /// 优先级：草稿审核 > 编辑娃娃资料（与拆分前一致）。
  Widget? _buildParentDetail() {
    // 草稿审核覆盖层：优先级最高（即使切了侧栏也停在审核直到家长退出）
    final reviewing = _reviewingTask;
    if (reviewing != null) {
      final selected = ref.watch(selectedChildProvider);
      return ParentTaskReviewScreen(
        task: reviewing,
        defaultChildId: reviewing.childId ?? selected?.id,
        onBackToHome: _backToHomeFromReview,
        onNavigateToPractice: (task) {
          // 仅家长显式点「查看练习」时进入。默认进只读预览，
          // 不直接进入可作答态，避免误代答/代打卡污染娃娃数据。
          setState(() => _reviewingTask = null);
          _navigateToPractice(task, preview: true);
        },
      );
    }
    // 编辑娃娃资料覆盖层（WF-5）：优先级次于审核层
    final editing = _editingChild;
    if (editing != null) {
      return ChildFormScreen(
        mode: ChildFormMode.edit,
        child: editing,
        onSaved: _onChildFormSaved,
        onBack: () => setState(() => _editingChild = null),
      );
    }
    return null;
  }

  /// 家长端主栏（master）：侧栏当前选中的页面。
  ///
  /// 详情覆盖层不再吃掉本栏——大屏下两者并排，家长可以在左侧直接换一条继续看；
  /// 中屏 / 紧凑下由壳用详情整幅顶替本栏，观感与拆分前完全一致。
  Widget _buildParentPage() {
    if (_showProfile) {
      return ProfileScreen(user: widget.user, onLogout: widget.onLogout);
    }
    return switch (_parentNavIndex) {
      0 => ParentOverviewView(
          onNavigateToReview: _navigateToReview,
          // 空态出口：概览与任务页的「去布置任务」都落到同一个目的地。
          onNavigateToCreate: () => _parentTap(1),
        ),
      // 生成成功后不直接跳 PracticeScreen，改跳 ParentTaskReviewScreen
      1 => ParentTaskFormView(
          onNavigateToReview: _navigateToReview,
        ),
      2 => const ParentWrongQuestionsView(),
      3 => const ParentTutorLogsView(),
      5 => ChildFormScreen(
          mode: ChildFormMode.create,
          onSaved: _onChildFormSaved,
          onBack: () => setState(() {
            _editingChild = null;
            _parentNavIndex = 0;
          }),
        ),
      6 => ParentQuestionBankView(
          onNavigateToReview: _navigateToReview,
        ),
      7 => const ParentModelManagementScreen(),
      8 => ParentTasksView(
          onNavigateToReview: _navigateToReview,
          onNavigateToCreate: () => _parentTap(1),
        ),
      _ => const SizedBox(),
    };
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
  List<AdaptiveNavDestination> _parentDestinations(int activeIndex) => [
    AdaptiveNavDestination(
        icon: LucideIcons.layoutDashboard,
        label: '概览',
        active: activeIndex == 0,
        onTap: () => _parentTap(0)),
    AdaptiveNavDestination(
        icon: LucideIcons.listTodo,
        label: '任务',
        active: activeIndex == 8,
        onTap: () => _parentTap(8)),
    AdaptiveNavDestination(
        icon: LucideIcons.pencil,
        label: '布置任务',
        active: activeIndex == 1,
        onTap: () => _parentTap(1)),
    AdaptiveNavDestination(
        icon: LucideIcons.bookOpen,
        label: '错题本',
        active: activeIndex == 2,
        onTap: () => _parentTap(2)),
    AdaptiveNavDestination(
        icon: LucideIcons.sparkles,
        label: 'AI 答疑记录',
        active: activeIndex == 3,
        onTap: () => _parentTap(3)),
    AdaptiveNavDestination(
        icon: LucideIcons.library,
        label: '题库',
        active: activeIndex == 6,
        onTap: () => _parentTap(6)),
    AdaptiveNavDestination(
        icon: LucideIcons.cpu,
        label: '模型管理',
        active: activeIndex == 7,
        onTap: () => _parentTap(7)),
  ];

  void _parentTap(int index) {
    // 任何侧栏导航都先关闭复核 / 编辑覆盖层。两者渲染优先级高于 _parentNavIndex，
    // 不清掉会挡住页面切换（编辑层尤其明显：点左侧菜单页面不跟随切换）。
    if (_reviewingTask != null || _editingChild != null) {
      setState(() {
        _reviewingTask = null;
        _editingChild = null;
      });
    }
    _onParentNavTap(index);
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

  AdaptiveNavDestination _profileDestination() => AdaptiveNavDestination(
        icon: LucideIcons.userRound,
        label: '我的',
        active: _showProfile,
        onTap: _onProfileTap,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.user.isParent) {
      // 复核覆盖层期间，侧栏高亮跟随来源页（_parentNavIndex 保持不变）。
      final activeIndex = _parentNavIndex;
      return AdaptiveShell(
        mode: AppUserMode.parent,
        destinations: _parentDestinations(activeIndex),
        profileDestination: _profileDestination(),
        sidebarTop: ParentChildSelector(
          onNavigateToAddChild: _onNavigateToAddChild,
          onNavigateToEditChild: _onNavigateToEditChild,
        ),
        sidebarBottom: AdaptiveUserBlock(
          user: widget.user,
          onProfileTap: _onProfileTap,
          subtitle: '家长账号',
        ),
        body: _buildParentPage(),
        detail: _buildParentDetail(),
      );
    }

    return AdaptiveShell(
      mode: AppUserMode.child,
      destinations: _childDestinations(_childNavIndex),
      profileDestination: _profileDestination(),
      sidebarBottom: AdaptiveUserBlock(
        user: widget.user,
        onProfileTap: _onProfileTap,
        subtitle: '${widget.user.grade ?? '?'}年级',
      ),
      body: _buildChildView(),
    );
  }
}
