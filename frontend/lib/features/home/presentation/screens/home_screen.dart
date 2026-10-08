import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/presentation/shell_navigation.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/adaptive_shell.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../students/providers/students_provider.dart';
import '../../../students/presentation/screens/student_form_screen.dart';
import '../../../students/presentation/screens/student_management_screen.dart';
import '../../../analytics/presentation/screens/analytics_screen.dart';
import '../../../assistant/presentation/screens/assistant_chat_page.dart';
import '../../../export/domain/export_repository.dart';
import '../../../export/presentation/export_preview_page.dart';
import '../../../practice/presentation/screens/practice_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../review/presentation/screens/review_screen.dart';
import '../../../review/presentation/screens/wrong_questions_screen.dart';
import '../../../model_management/presentation/screens/teacher_model_management_screen.dart';
import '../providers/home_notifier.dart';
import '../providers/teacher_tasks_notifier.dart';
import '../teacher_pages.dart';
import '../widgets/teacher/scene_library_detail_view.dart';
import '../widgets/teacher/scene_library_view.dart';
import '../widgets/teacher/knowledge_point_scene_editor.dart';
import '../screens/student_detail_screen.dart';
import '../screens/teacher_task_review_screen.dart';
import 'teacher_destinations.dart';
import '../widgets/student_home.dart';
import '../widgets/teacher/teacher_overview_view.dart';
import '../widgets/teacher/teacher_task_form_view.dart';
import '../widgets/teacher/teacher_question_bank_view.dart';
import '../widgets/teacher/teacher_tasks_view.dart';
import '../widgets/teacher/material_library_view.dart';
import '../../../../features/courseware/presentation/screens/courseware_center_screen.dart';
import 'student_mastery_screen.dart';
import '../../../../shared/widgets/app_actions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.user, required this.onLogout});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// 教师端当前页面——导航的**唯一**事实源（ADR-0059）。
  ///
  /// 以前是三个并列状态：侧栏索引 + 审核 / 编辑覆盖层 + `_showProfile` 布尔。三者并存
  /// 就需要「谁压谁」的裁决，而裁决散在各回调里（侧栏点击记得清覆盖层、底部「我的」
  /// 忘了清 → 审核中看到的是审核页，个人信息压根没进渲染树）。合成 `sealed` 后各入口
  /// 天然互斥，且 `switch` 穷尽性由编译器保证。
  TeacherPage _teacherPage = const OverviewPage();

  int _childNavIndex = 0;
  bool _showProfile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.user.isTeacher) {
        ref.read(studentsNotifierProvider.notifier).loadChildren();
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
            // maybePop 而非 pop：练习路由已被移除时为 no-op，绝不弹根导航栈的 home（_history 断言）。
            Navigator.of(context).maybePop();
            // 完成做题后统一刷新所有受影响的学生端数据：今日任务 / 待复习 /
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
  void _go(TeacherPage page) => setState(() => _teacherPage = page);

  /// R3：生成草稿后进审核页。[back] 记下从哪儿进来，退出时回来源页而非一律回概览。
  void _navigateToReview(TaskModel draft) {
    final gen = ref.read(taskGenNotifierProvider.notifier);
    _go(TaskReviewPage(
      draft,
      classIds: gen.pendingClassIds,
      studentIds: gen.pendingStudentIds,
      back: highlightFor(_teacherPage),
    ));
  }

  void _backToHomeFromReview() {
    // 刷新教师侧概览（作废/派发后列表/进度可能变动）
    // 概览与任务页共用同一份状态，这里按「全部状态」重新拉第一页即可。
    ref
        .read(teacherTasksNotifierProvider.notifier)
        .load(kAllTaskStatuses);
    _go(highlightFor(_teacherPage));
  }

  /// StudentFormScreen 保存后的统一回调（创建 + 编辑共用）。
  void _onChildFormSaved(UserModel saved) {
    // 列表已在 notifier 内刷新；回到首页/关闭编辑层。
    _go(const OverviewPage());
  }

  void _onNavigateToEditStudent(UserModel child) {
    _go(EditStudentPage(child));
  }

  /// 「我的」入口——**两个角色共用**（侧栏底部用户区 / 紧凑档底栏）。
  ///
  /// 必须按角色分派：教师端是 [TeacherPage] 的一个分支，学生端仍是「页签 +
  /// [_showProfile] 布尔」的二选一（见 [_buildChildView]）。⚠️ 只写教师端那份，
  /// 学生端点「我的」就毫无反应。守卫 `test/teacher_nav_single_source_test.dart`。
  void _onProfileTap() {
    if (widget.user.isTeacher) {
      _go(const ProfilePage());
      return;
    }
    setState(() => _showProfile = true);
  }

  /// 侧栏头部「添加学生」。
  void _onNavigateToAddStudent() => _go(const AddStudentPage());

  /// 切换学生端 Tab：改变 IndexedStack 索引，并在该页「变为可见」时重新拉取最新数据。
  ///
  /// 关键修复：学生端所有 Tab 被同一 [IndexedStack] 常驻挂载，[initState] 只在 App
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

  /// 教师端主栏：把 [_teacherPage] 翻成页面。`switch` 穷尽性由 `sealed` 保证——新增
  /// 页面忘记登记会编译失败，不会出现「点了没反应」。
  Widget _buildTeacherPage() {
    final page = _teacherPage;
    return switch (page) {
      OverviewPage() => TeacherOverviewView(
          onNavigateToReview: _navigateToReview,
          // 空态出口：概览与任务页的「去布置任务」都落到同一个目的地。
          onNavigateToCreate: () => _go(const CreateTaskPage()),
          // 待办卡片深链：按 Tab 进任务列表（0=草稿箱 / 1=进行中 / 2=已完成）。
          onNavigateToList: (tab) => _go(TaskListPage(initialTab: tab)),
        ),
      // ADR-0057：生成页不再接跳转回调——收尾（含进草稿页）由本页的监听统一负责。
      CreateTaskPage() => const TeacherTaskFormView(),
      AddStudentPage() => StudentFormScreen(
          mode: ChildFormMode.create,
          onSaved: _onChildFormSaved,
          onBack: () => _go(const OverviewPage()),
        ),
      EditStudentPage(child: final child) => StudentFormScreen(
          mode: ChildFormMode.edit,
          child: child,
          onSaved: _onChildFormSaved,
          onBack: () => _go(const OverviewPage()),
        ),
      QuestionBankPage() => TeacherQuestionBankView(
          onNavigateToReview: _navigateToReview,
        ),
      MaterialLibraryPage() => const MaterialLibraryView(),
      CoursewarePage() => const CoursewareCenterScreen(),
      SceneLibraryPage() => TeacherSceneLibraryView(
          onOpenScene: (kind) => _go(SceneLibraryDetailPage(kind)),
        ),
      SceneLibraryDetailPage(kind: final kind) => TeacherSceneLibraryDetailView(
          kind: kind,
          onBack: () => _go(const SceneLibraryPage()),
        ),
      SceneLibraryEditorPage(
        kpId: final kpId,
        kpName: final kpName,
        subject: final subject,
        grade: final grade,
        semester: final semester,
        initialScenes: final initialScenes,
        back: final back,
      ) =>
        // 内容兜底走 Align(topCenter)+ConstrainedBox，不可 Center（ADR-003 内容兜底纪律）；
        // 编辑器原本为 560 宽弹窗设计，作为页仍夹到 560 以保持既定排版。关闭走
        // `onBack`（统一回 [back]），不裸 Navigator.pop 弹根栈。
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: KnowledgePointSceneEditor(
                kpId: kpId,
                kpName: kpName,
                subject: subject,
                grade: grade,
                semester: semester,
                initialScenes: initialScenes,
                onBack: () => _go(back),
              ),
            ),
          ),
        ),
      ModelsPage() => const TeacherModelManagementScreen(),
      StudentManagementPage() => StudentManagementScreen(
          onOpenStudent: (id) {
            _go(StudentDetailPage(id,
                initialTab: StudentDetailTab.wrongQuestions));
          },
          onAddStudent: _onNavigateToAddStudent),
      AnalyticsPage() => const AnalyticsScreen(),
      TaskListPage(initialTab: final tab) => TeacherTasksView(
          onNavigateToReview: _navigateToReview,
          onNavigateToCreate: () => _go(const CreateTaskPage()),
          initialTab: tab,
        ),
      TaskReviewPage(task: final task) => TeacherTaskReviewScreen(
          task: task,
          defaultChildId: task.studentId,
          onBackToHome: _backToHomeFromReview,
          onNavigateToPractice: (t) {
            // 仅教师显式点「查看练习」时进入。默认进只读预览，
            // 不直接进入可作答态，避免误代答/代打卡污染学生数据。
            _go(page.back);
            _navigateToPractice(t, preview: true);
          },
        ),
      ProfilePage() => ProfileScreen(user: widget.user, onLogout: widget.onLogout),
      StudentDetailPage(studentId: final id, initialTab: final tab) =>
        StudentDetailScreen(
          studentId: id,
          initialTab: tab,
          onBack: () => _go(const OverviewPage()),
          onEditStudent: _onNavigateToEditStudent,
        ),
    };
  }

  /// 教师端主栏 + 常驻「出题进行中」指示条（ADR-0057 P1）。
  ///
  /// 出题的 SSE 在 [taskGenNotifierProvider]（非 autoDispose）里跑，切 Tab 不中断；
  /// 但旧实现里指示 UI 全在生成页，教师一走就看不见、回来也不知道进度。这里把进度条
  /// 挂在壳层、跨 Tab 常驻，并带一个随时可点的停止按钮（强制关闭后台生成，保留已出题）。
  Widget _buildTeacherBody() {
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
        Expanded(child: _buildTeacherPage()),
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

  /// 学生端复习页的导出入口（ADR-0052）：屏幕上到期的是哪些题，纸上就是哪些题。
  ///
  /// 注入而非页内自建的原因见 [ReviewScreen.onExportDue]——按 ADR-0037，
  /// `features/review` 不得 import `features/export`，关联只能在 home 组合根建立。
  ///
  /// 请求不带 `studentId`：学生端的作用域由服务端按调用者 token 钉死
  /// （来源 = wrong_book、学生 = 自己），客户端无从越过自己的错题本。
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

  // 导航目的地构造器（`teacher_destinations.dart`）：方法体抽出后本文件回到
  // ADR-0058 基线内，新增「资料库」入口不再顶破棘轮。
  NavigationDestinations get _destinations => NavigationDestinations(
        go: _go,
        goChildTab: _switchChildTab,
        goProfile: _onProfileTap,
        genTrailing: _genTrailing,
      );

  Widget _buildChildView() {
    if (_showProfile) {
      return ProfileScreen(user: widget.user, onLogout: widget.onLogout);
    }
    return IndexedStack(
      index: _childNavIndex,
      children: [
        StudentHome(
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
        StudentMasteryScreen(user: widget.user),
      ],
    );
  }

  /// 壳目的地 → 教师端页面；学生端没有这些目的地（返回 null，意图被丢弃）。
  ///
  /// 这里是 [_destinations.teacher] 之外**第二个**写入口（助手卡片跳转），所以映射
  /// 只此一处，不把编号散出去。
  TeacherPage? _teacherPageFor(ShellDestination destination) {
    if (!widget.user.isTeacher) return null;
    return switch (destination) {
      ShellDestination.teacherCreateTask => const CreateTaskPage(),
      ShellDestination.teacherTaskList => const TaskListPage(),
      ShellDestination.teacherQuestionBank => const QuestionBankPage(),
    };
  }

  /// 壳外页面（push 出来的助手整页）请求的跳转：翻成页面后走 [_go]，与点侧栏
  /// 是同一条路径（同一个状态，没有需要额外清理的覆盖层）。
  ///
  /// 无条件注册（不放进 `isTeacher` 分支）：ref.listen 的调用次数在多次 build
  /// 之间必须一致，条件注册会让「角色分支变化」时的订阅数量对不上。
  void _listenShellNavigation() {
    ref.listen(shellNavigationProvider, (_, next) {
      if (next == null) return;
      // 先消费再执行：不清空的话下一次 rebuild 会重复触发同一次跳转。
      ref.read(shellNavigationProvider.notifier).consume();
      final page = _teacherPageFor(next);
      if (page != null) _go(page);
    });
  }

  /// ADR-0057：出题的**收尾动作**放在这一层，不放生成页。
  ///
  /// 生成页（`TeacherTaskFormView`）只在该侧栏索引挂载，教师一切走它就被卸载；
  /// 而本页不会。凡是「任务结束了总得有人收尾」的事（提示、重置、刷新、进草稿页）
  /// 都必须挂在生命周期更长的那一层——挂在页面里，人一走就成了无人区：
  /// 成功不提示、失败静默，落库倒是照常发生。生成页只负责渲染 state。
  void _listenTaskGen() {
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
        // 教师以为「语文没出」是系统漏了，而不是生成失败。
        if (next.isShort) {
          AppToast.error(context, next.shortMessage);
        } else {
          AppToast.show(context, '已保存草稿，共 ${next.task.questions.length} 道题');
        }
        ref.read(taskGenNotifierProvider.notifier).reset();
        _navigateToReview(next.task);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenShellNavigation();
    _listenTaskGen();

    if (widget.user.isTeacher) {
      // ADR-0057 P1：出题在壳这一层 watch，跨 Tab 常驻可见。
      final gen = ref.watch(taskGenNotifierProvider);
      return AdaptiveShell(
        mode: AppUserMode.teacher,
        destinations: _destinations.teacher(_teacherPage, gen),
        profileDestination: _destinations.profile(active: _teacherPage is ProfilePage),
        // ADR-0070：顶部学生选择器菜单已移除，当前学生改由导航进入学生时写入
        // （见 _setCurrentStudent），不再有常驻切换/添加菜单。
        sidebarTop: null,
        sidebarBottom: AdaptiveUserBlock(
          user: widget.user,
          onProfileTap: _onProfileTap,
          subtitle: '教师账号',
        ),
        body: _buildTeacherBody(),
      );
    }

    return AdaptiveShell(
      mode: AppUserMode.student,
      // 显示个人信息时页签一律取消高亮：否则「复习」和「我的」会同时亮着。
      destinations: _destinations.child(_showProfile ? -1 : _childNavIndex),
      profileDestination: _destinations.profile(active: _showProfile),
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
// 教师端导航状态（ADR-0059）
// ---------------------------------------------------------------------------
