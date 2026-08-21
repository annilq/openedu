import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../children/domain/providers/children_provider.dart';
import '../../../practice/presentation/screens/practice_screen.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../review/presentation/screens/review_screen.dart';
import '../../../review/presentation/screens/wrong_questions_screen.dart';
import '../../../tutor/presentation/screens/tutor_chat_screen.dart';
import '../providers/home_notifier.dart';
import '../widgets/parent_dashboard.dart';
import '../widgets/child_home.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.user, required this.onLogout});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 初始加载
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
            // 刷新今日任务
            ref.read(todayTasksNotifierProvider.notifier).load();
          },
        ),
      ),
    );
  }

  void _navigateToReview() {
    Navigator.of(context)
        .push(CupertinoPageRoute(builder: (_) => const ReviewScreen()))
        .then((_) {
      if (!mounted) return;
      ref.read(dueReviewNotifierProvider.notifier).load();
    });
  }

  void _navigateToWrongQuestions() {
    Navigator.of(context)
        .push(CupertinoPageRoute(builder: (_) => const WrongQuestionsScreen()))
        .then((_) {
      if (!mounted) return;
      ref.read(dueReviewNotifierProvider.notifier).load();
    });
  }

  void _navigateToTutor() {
    Navigator.of(context)
        .push(CupertinoPageRoute(
          builder: (_) => TutorChatScreen(user: widget.user),
        ))
        .then((_) {
      if (!mounted) return;
      ref.read(dueReviewNotifierProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CupertinoNavigationBar(
          middle: Text(
            widget.user.isParent
                ? '家长端 · ${widget.user.displayName}'
                : '${widget.user.displayName}的学习',
            overflow: TextOverflow.ellipsis,
          ),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: widget.onLogout,
            child: const Icon(CupertinoIcons.square_arrow_right),
          ),
        ),
        Expanded(
          child: widget.user.isParent
              ? ParentDashboard(
                  user: widget.user,
                  onNavigateToPractice: _navigateToPractice,
                )
              : ChildHome(
                  user: widget.user,
                  onNavigateToPractice: _navigateToPractice,
                  onNavigateToReview: _navigateToReview,
                  onNavigateToWrongQuestions: _navigateToWrongQuestions,
                  onNavigateToTutor: _navigateToTutor,
                ),
        ),
      ],
    );
  }
}
