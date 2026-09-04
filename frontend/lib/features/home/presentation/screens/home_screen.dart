import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/adaptive_shell.dart';
import '../../../children/domain/providers/children_provider.dart';
import '../../../children/presentation/screens/child_form_screen.dart';
import '../../../practice/presentation/screens/practice_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../review/presentation/screens/review_screen.dart';
import '../../../review/presentation/screens/wrong_questions_screen.dart';
import '../../../tutor/presentation/screens/tutor_chat_screen.dart';
import '../../../tutor/presentation/screens/parent_model_management_screen.dart';
import '../providers/home_notifier.dart';
import '../providers/parent_tasks_notifier.dart';
import '../providers/selected_child_provider.dart';
import '../screens/parent_task_review_screen.dart';
import '../widgets/child_home.dart';
import '../widgets/parent/parent_child_selector.dart';
import '../widgets/parent/parent_overview_view.dart';
import '../widgets/parent/parent_task_form_view.dart';
import '../widgets/parent/parent_tutor_logs_view.dart';
import '../widgets/parent/parent_tutor_quota_view.dart';
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
    ref.read(parentTasksNotifierProvider.notifier).load();
    final selected = ref.read(selectedChildProvider);
    if (selected != null) {
      ref.read(progressNotifierProvider.notifier).load(selected.id);
      ref.read(masteryNotifierProvider.notifier).load(selected.id);
      ref
          .read(parentWrongQuestionsProvider.notifier)
          .load(childId: selected.id);
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
    setState(() => _showProfile = true);
  }

  void _onNavigateToAddChild() {
    setState(() {
      _showProfile = false;
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
      case 3: // AI 伴学：会话由 TutorChatScreen 自我管理，无需全局刷新
        break;
      case 4: // 学科掌握度
        ref.read(masteryNotifierProvider.notifier).load(widget.user.id);
    }
  }

  Widget _buildParentView() {
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
      );
    }
    if (_showProfile) {
      return ProfileScreen(user: widget.user, onLogout: widget.onLogout);
    }
    return switch (_parentNavIndex) {
      0 => ParentOverviewView(onNavigateToReview: _navigateToReview),
      // 生成成功后不直接跳 PracticeScreen，改跳 ParentTaskReviewScreen
      1 => ParentTaskFormView(
          onNavigateToReview: _navigateToReview,
        ),
      2 => const ParentWrongQuestionsView(),
      3 => const ParentTutorLogsView(),
      4 => const ParentTutorQuotaView(),
      5 => ChildFormScreen(
          mode: ChildFormMode.create,
          onSaved: _onChildFormSaved,
        ),
      6 => ParentQuestionBankView(
          onNavigateToReview: _navigateToReview,
        ),
      7 => const ParentModelManagementScreen(),
      8 => ParentTasksView(
          onNavigateToReview: _navigateToReview,
        ),
      _ => const SizedBox(),
    };
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
        const ReviewScreen(showBack: false),
        const WrongQuestionsScreen(showBack: false),
        TutorChatScreen(user: widget.user, showBack: false),
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
        icon: LucideIcons.shieldCheck,
        label: 'AI 管控',
        active: activeIndex == 4,
        onTap: () => _parentTap(4)),
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
    // 审核页内点击导航不直接切，先返回首页
    if (_reviewingTask != null) {
      setState(() => _reviewingTask = null);
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
        label: 'AI 伴学',
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
        body: _buildParentView(),
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
