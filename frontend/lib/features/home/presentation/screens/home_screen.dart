import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/desktop_shell.dart';
import '../../../children/domain/providers/children_provider.dart';
import '../../../children/presentation/screens/child_form_screen.dart';
import '../../../practice/presentation/screens/practice_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../review/presentation/screens/review_screen.dart';
import '../../../review/presentation/screens/wrong_questions_screen.dart';
import '../../../tutor/presentation/screens/tutor_chat_screen.dart';
import '../providers/home_notifier.dart';
import '../providers/selected_child_provider.dart';
import '../screens/parent_task_review_screen.dart';
import '../widgets/child_home.dart';
import '../widgets/child_sidebar.dart';
import '../widgets/parent/parent_overview_view.dart';
import '../widgets/parent/parent_sidebar.dart';
import '../widgets/parent/parent_task_form_view.dart';
import '../widgets/parent/parent_tutor_logs_view.dart';
import '../widgets/parent/parent_tutor_quota_view.dart';
import '../widgets/parent/parent_question_bank_view.dart';
import '../widgets/parent/parent_wrong_questions_view.dart';

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

  void _navigateToPractice(TaskModel task) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => PracticeScreen(
          task: task,
          onDone: () {
            Navigator.of(context).pop();
            ref.read(todayTasksNotifierProvider.notifier).load();
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

  void _onChildNavTap(int index) {
    setState(() {
      _showProfile = false;
      _childNavIndex = index;
    });
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
          // 派发完成后关审核层，并跳 PracticeScreen 预览
          setState(() => _reviewingTask = null);
          _navigateToPractice(task);
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
      0 => const ParentOverviewView(),
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
          onNavigateToReview: () => setState(() => _childNavIndex = 1),
          onNavigateToWrongQuestions: () => setState(() => _childNavIndex = 2),
          onNavigateToTutor: () => setState(() => _childNavIndex = 3),
        ),
        const ReviewScreen(showBack: false),
        const WrongQuestionsScreen(showBack: false),
        TutorChatScreen(user: widget.user, showBack: false),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user.isParent) {
      return DesktopShell(
        sidebar: ParentSidebar(
          user: widget.user,
          selectedIndex: _reviewingTask != null ? 1 : _parentNavIndex,
          onNavTap: (index) {
            // 审核页内点击侧栏不直接切，先返回首页
            if (_reviewingTask != null) {
              setState(() => _reviewingTask = null);
            }
            _onParentNavTap(index);
          },
          onProfileTap: _onProfileTap,
          onNavigateToAddChild: _onNavigateToAddChild,
          onNavigateToEditChild: _onNavigateToEditChild,
        ),
        body: _buildParentView(),
      );
    }

    return DesktopShell(
      sidebar: ChildSidebar(
        user: widget.user,
        selectedIndex: _childNavIndex,
        onNavTap: _onChildNavTap,
        onProfileTap: _onProfileTap,
      ),
      body: _buildChildView(),
    );
  }
}

