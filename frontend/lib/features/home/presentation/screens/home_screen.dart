import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/desktop_shell.dart';
import '../../../children/domain/providers/children_provider.dart';
import '../../../children/presentation/providers/children_notifier.dart';
import '../../../children/presentation/screens/add_child_screen.dart';
import '../../../practice/presentation/screens/practice_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../review/presentation/screens/review_screen.dart';
import '../../../review/presentation/screens/wrong_questions_screen.dart';
import '../../../tutor/presentation/screens/tutor_chat_screen.dart';
import '../providers/home_notifier.dart';
import '../providers/selected_child_provider.dart';
import '../widgets/child_home.dart';
import '../widgets/child_sidebar.dart';
import '../widgets/parent/parent_overview_view.dart';
import '../widgets/parent/parent_sidebar.dart';
import '../widgets/parent/parent_task_form_view.dart';
import '../widgets/parent/parent_tutor_logs_view.dart';
import '../widgets/parent/parent_tutor_quota_view.dart';
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
      MaterialPageRoute(
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

  void _onChildCreated(String newId) {
    final state = ref.read(childrenNotifierProvider);
    if (state is ChildrenLoaded) {
      for (final c in state.children) {
        if (c.id == newId) {
          ref
              .read(selectedChildProvider.notifier)
              .select(c.id, c.grade ?? 2);
          break;
        }
      }
    }
    setState(() {
      _showProfile = false;
      _parentNavIndex = 0;
    });
  }

  void _onChildNavTap(int index) {
    setState(() {
      _showProfile = false;
      _childNavIndex = index;
    });
  }

  Widget _buildParentView() {
    if (_showProfile) {
      return ProfileScreen(user: widget.user, onLogout: widget.onLogout);
    }
    return switch (_parentNavIndex) {
      0 => const ParentOverviewView(),
      1 => ParentTaskFormView(onNavigateToPractice: _navigateToPractice),
      2 => const ParentWrongQuestionsView(),
      3 => const ParentTutorLogsView(),
      4 => const ParentTutorQuotaView(),
      5 => AddChildScreen(
          showBack: false,
          onCreated: _onChildCreated,
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
          selectedIndex: _parentNavIndex,
          onNavTap: _onParentNavTap,
          onProfileTap: _onProfileTap,
          onNavigateToAddChild: _onNavigateToAddChild,
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
