import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../children/domain/providers/children_provider.dart';
import '../../../practice/presentation/screens/practice_screen.dart';
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
            // 刷新今日任务
            ref.read(todayTasksNotifierProvider.notifier).load();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user.isParent
            ? '家长端 · ${widget.user.displayName}'
            : '${widget.user.displayName}的学习'),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
          ),
        ],
      ),
      body: widget.user.isParent
          ? ParentDashboard(
              user: widget.user,
              onNavigateToPractice: _navigateToPractice,
            )
          : ChildHome(
              user: widget.user,
              onNavigateToPractice: _navigateToPractice,
            ),
    );
  }
}
