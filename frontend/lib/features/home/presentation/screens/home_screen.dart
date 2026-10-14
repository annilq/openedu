import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/presentation/shell_navigation.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/presentation/resource.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/adaptive_shell.dart';
import '../../../../shared/widgets/app_content_frame.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../students/providers/students_provider.dart';
import '../../../students/presentation/screens/student_form_screen.dart';
import '../../../students/presentation/screens/student_management_screen.dart';
import '../../../classes/presentation/screens/class_management_screen.dart';
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
import '../../providers/knowledge_manage_provider.dart';
import '../teacher_pages.dart';
import '../teacher_nav_stack.dart';
import '../page_labels.dart';
import '../child_pages.dart';
import '../widgets/teacher/scene_library_detail_view.dart';
import '../widgets/teacher/scene_library_view.dart';
import 'package:kids_learn/shared/features/materials/presentation/widgets/teacher/knowledge_point_scene_editor.dart';
import '../screens/student_detail_screen.dart';
import '../screens/teacher_task_review_screen.dart';
import 'teacher_destinations.dart';
import '../widgets/student_home.dart';
import '../widgets/teacher/teacher_overview_view.dart';
import '../widgets/teacher/teacher_task_form_view.dart';
import '../widgets/teacher/generation_banner.dart';
import '../widgets/teacher/teacher_question_bank_view.dart';
import '../widgets/teacher/teacher_tasks_view.dart';
import '../widgets/teacher/material_library_view.dart';
import '../../../../features/courseware/presentation/screens/courseware_center_screen.dart';
import '../../../../features/courseware/presentation/screens/asset_library_screen.dart';
import '../../../../features/assistant/presentation/widgets/run_trace_detail_view.dart';
import '../../../../features/assistant/presentation/widgets/run_trace_view.dart';
import 'student_mastery_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.user, required this.onLogout});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// 教师端导航历史——**唯一**的事实源（ADR-0059）。
  ///
  /// 以前是三个并列状态：侧栏索引 + 审核 / 编辑覆盖层 + `_showProfile` 布尔。三者并存
  /// 就需要「谁压谁」的裁决，而裁决散在各回调里（侧栏点击记得清覆盖层、底部「我的」
  /// 忘了清 → 审核中看到的是审核页，个人信息压根没进渲染树）。合成 `sealed` 后各入口
  /// 天然互斥，且 `switch` 穷尽性由编译器保证。
  ///
  /// 引入返回栈（ticket 03）之后不变式**没有放松，反而更紧**：`_teacherPage` 不是
  /// 第二个字段，它是 [TeacherNavStack.current]（栈顶）的只读投影。栈只是历史——
  /// 不存在「栈顶说 A、当前页面字段说 B」这种需要裁决的状态。
  final TeacherNavStack _teacherNav = TeacherNavStack();

  TeacherPage get _teacherPage => _teacherNav.current;

  /// 学生端当前页面——导航的**唯一**事实源（ADR-0059，LCC-09）。取代原先
  /// 「页签索引 + [_showProfile] 布尔」的二选一：布尔与索引并存等于两个真源，需要
  /// 「谁压谁」的裁决且裁决散落各回调，易漏（点了「我的」忘了清页签 → 两个同时亮）。
  ChildPage _childPage = const ChildHomePage();

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

  /// **下钻**出口：入栈。新增下钻页**零义务**——不需要声明回落目标，退回哪儿由
  /// 历史决定（ticket 03：返回从「每个页面自己记得声明」变成结构默认）。
  void _go(TeacherPage page) => setState(() => _teacherNav.push(page));

  /// **切换一级入口**出口：替换当前页面并清空历史。
  ///
  /// 侧栏每一项、底部「我的」、助手卡片跳转都走这条。与 [_go] 分开是因为它们不是
  /// 「从当前页往下钻」而是「换一个入口」：不清历史的话，切到「题库」后按返回会
  /// 跨入口弹回上一次的班内学生页。
  void _goEntry(TeacherPage page) => setState(() => _teacherNav.reset(page));

  /// 回退一步：出栈。已在根页面（概览）时不动——[build] 里的 [PopScope] 据此把
  /// 返回键交回系统。
  void _back() => setState(() => _teacherNav.pop());

  /// R3：生成草稿后进审核页。审核是从当前页下钻进去的，退出时由 [_back] 回到来源页。
  void _navigateToReview(TaskModel draft) {
    final gen = ref.read(taskGenNotifierProvider.notifier);
    _go(TaskReviewPage(
      draft,
      classIds: gen.pendingClassIds,
      studentIds: gen.pendingStudentIds,
    ));
  }

  void _backToHomeFromReview() {
    // 刷新教师侧概览（作废/派发后列表/进度可能变动）
    // 概览与任务页共用同一份状态，这里按「全部状态」重新拉第一页即可。
    ref
        .read(teacherTasksNotifierProvider.notifier)
        .load(kAllTaskStatuses);
    _back();
  }

  void _onNavigateToEditStudent(UserModel child) =>
      _go(EditStudentPage(child));

  /// 系统返回键 / 外接键盘 Esc / 系统侧滑手势——三者在框架内共用这一个入口。
  ///
  /// 全 App 只有一个 route（ADR-0059），返回键原本**直接退出应用**：教师在
  /// 「班级 → 班内学生 → 学生详情 → 编辑学生」四级链上按一下，四级全丢（P0-2）。
  /// 这里把它翻译成壳内的一次回退。
  ///
  /// 返回「壳是否消费了这一次返回」：根页面返回 false，由 [_onSystemBack] 交回系统
  /// ——否则用户按返回键退出应用的能力被白白拿走。
  bool _handleSystemBack() {
    if (widget.user.isTeacher) {
      if (!_teacherNav.canPop) return false;
      _back();
      return true;
    }
    // 学生端：页签不是下钻链，非首页一律回首页；已在首页则同样交回系统。
    if (_childPage is ChildHomePage) return false;
    _switchChildTab(0);
    return true;
  }

  /// [PopScope] 的回调：决定这一下系统返回是壳内回退还是交回系统。
  void _onSystemBack(bool didPop, Object? result) {
    if (didPop) return;
    if (_handleSystemBack()) return;
    // 根页面：交回系统退出应用。这里**不能**用 `Navigator.pop`——根导航栈只有一条
    // 路由，弹掉它等于把整棵渲染树拆了（下一次重建撞 `_history.isNotEmpty` 断言，
    // 守卫见 `test/tab_screen_no_root_pop_test.dart`）。
    SystemNavigator.pop();
  }

  /// 「我的」入口——**两个角色共用**（侧栏底部用户区 / 紧凑档底栏）。
  ///
  /// 必须按角色分派：教师端是 [TeacherPage] 的一个分支，学生端也已合成为 [ChildPage]
  /// 单一状态（见 [_buildChildView]）。⚠️ 只写教师端那份，学生端点「我的」就毫无反应。
  /// 守卫 `test/teacher_nav_single_source_test.dart`。
  void _onProfileTap() {
    if (widget.user.isTeacher) {
      _goEntry(const ProfilePage());
      return;
    }
    setState(() => _childPage = const ChildProfilePage());
  }

  /// 侧栏头部「添加学生」。[classId]/[className] 非空表示由班级下钻页发起
  /// （ADR-0086 ticket 06）：新建学生直接归入该班，保存后经 [_back] 回该班下钻页。
  void _onNavigateToAddStudent([String? classId, String? className]) =>
      _go(AddStudentPage(classId: classId, className: className));

  /// 切换学生端 Tab：改变 IndexedStack 索引，并在该页「变为可见」时重新拉取最新数据。
  ///
  /// 关键修复：学生端所有 Tab 被同一 [IndexedStack] 常驻挂载，[initState] 只在 App
  /// 启动那一刻跑一次（此时还没做过题 → 数据为空的旧快照）。切回 Tab 只翻转 index、
  /// 不会重跑 initState，所以必须在这里显式触发对应 provider 的 load()。
  void _switchChildTab(int index) {
    final page = childPageFromIndex(index);
    if (_childPage == page) return; // 已在该页，避免重复加载
    setState(() => _childPage = page);
    _refreshChildTab(page);
  }

  /// 按当前 [ChildPage] 派发对应 provider 的刷新（与屏幕 initState 中的首次加载保持一致）。
  void _refreshChildTab(ChildPage page) {
    switch (page) {
      case ChildHomePage():
        ref.read(todayTasksNotifierProvider.notifier).load();
        ref.read(dueReviewNotifierProvider.notifier).load();
      case ChildReviewPage():
        ref.read(dueReviewNotifierProvider.notifier).load();
      case ChildWrongQuestionsPage():
        ref.read(childWrongQuestionsProvider.notifier).load();
      case ChildMasteryPage():
        ref.read(masteryNotifierProvider.notifier).load(widget.user.id);
      case ChildProfilePage():
        // 个人信息页无额外取数。
        break;
    }
  }

  /// 教师端主栏：把 [_teacherPage] 翻成页面。`switch` 穷尽性由 `sealed` 保证——新增
  /// 页面忘记登记会编译失败，不会出现「点了没反应」。
  Widget _buildTeacherPage() {
    final page = _teacherPage;
    return switch (page) {
      OverviewPage() => TeacherOverviewView(
          onNavigateToReview: _navigateToReview,
          // 空态出口：概览与任务页的「去发布任务」都落到同一个目的地。
          onNavigateToCreate: () => _go(const CreateTaskPage()),
          // 待办卡片深链：按 Tab 进任务列表（0=草稿箱 / 1=进行中 / 2=已完成）。
          onNavigateToList: (tab) => _go(TaskListPage(initialTab: tab)),
        ),
      // ADR-0057：生成页不再接跳转回调——收尾（含进草稿页）由本页的监听统一负责。
      // 05：表单类页面用窄宽度（contentNarrow）居中，两侧不再大片留白。
      CreateTaskPage() => _narrow(const TeacherTaskFormView()),
      AddStudentPage() => _narrow(StudentFormScreen(
          mode: ChildFormMode.create,
          classId: page.classId,
          // 新建是下钻进去的，收尾统一出栈——不再需要「按 classId 猜回落页」的
          // 三元（旧 `_addStudentReturnPage`）：从哪个页面发起就回哪个页面。
          onSaved: (_) => _back(),
          onBack: _back,
        )),
      EditStudentPage(child: final child) => _narrow(StudentFormScreen(
          mode: ChildFormMode.edit,
          child: child,
          onSaved: (_) => _back(),
          onBack: _back,
        )),
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
          onBack: _back,
          onOpenKp: (kp) => _go(SceneLibraryEditorPage(
            kpId: kp.id,
            kpName: kp.name,
            subject: kp.subject,
            grade: kp.grade,
            semester: kp.semester,
            initialScenes: kp.scenes,
          )),
        ),
      SceneLibraryEditorPage(
        kpId: final kpId,
        kpName: final kpName,
        subject: final subject,
        grade: final grade,
        semester: final semester,
        initialScenes: final initialScenes,
      ) =>
        // 内容兜底走 Align(topCenter)+ConstrainedBox，不可 Center（ADR-003 内容兜底纪律）；
        // 编辑器原本为 560 宽弹窗设计，作为页仍夹到 560 以保持既定排版。关闭走
        // `onBack`，不裸 Navigator.pop 弹根栈。
        //
        // 关闭时顺手作废场景库清单缓存：编辑器经 `knowledgeManageProvider` 改的是
        // `kp.scenes`，与 `sceneLibraryProvider` 是两份数据，不失效的话回到详情页
        // 仍显示旧标题/图形（ADR-0073 来源仍是 kp.scenes，只是缓存未刷新）。
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
                onBack: () {
                  ref.invalidate(sceneLibraryProvider);
                  _back();
                },
              ),
            ),
          ),
        ),
      // ticket 08：模型管理 / 运行轨迹已不再是一级侧栏入口，改由「我的」页内系统分区
      // 入栈进入。它们本无返回按钮（原是侧栏根页），这里统一套一个返回头，使「返回」
      // 落回「我的」——单一出口，不裸 Navigator.pop 弹根栈。
      ModelsPage() => _withBackHeader(const TeacherModelManagementScreen()),
      AssetLibraryPage() => const AssetLibraryScreen(),
      StudentManagementPage() => StudentManagementScreen(
          onOpenStudent: (id) {
            _go(StudentDetailPage(id,
                initialTab: StudentDetailTab.wrongQuestions));
          },
          onAddStudent: _onNavigateToAddStudent),
      ClassManagementPage() => ClassManagementScreen(
          onOpenClass: (id, name) => _go(ClassStudentsPage(id, name)),
        ),
      ClassStudentsPage(classId: final cid, className: final cname) =>
        StudentManagementScreen(
          classId: cid,
          className: cname,
          // 下钻页的返回统一出栈（单一出口，不裸 Navigator.pop）。
          onBack: _back,
          onOpenStudent: (id) {
            _go(StudentDetailPage(id,
                initialTab: StudentDetailTab.wrongQuestions));
          },
          onAddStudent: () => _onNavigateToAddStudent(cid, cname),
        ),
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
            _back();
            _navigateToPractice(t, preview: true);
          },
        ),
      ProfilePage() => _narrow(ProfileScreen(
          user: widget.user,
          onLogout: widget.onLogout,
          // ticket 08：系统项（模型管理 / 运行轨迹）从侧栏搬进「我的」页内分区。
          // 走 _go（入栈）而非 _goEntry，返回落点仍是「我的」。
          onNavigateToModels: () => _go(const ModelsPage()),
          onNavigateToRunTrace: () => _go(const RunTracePage()),
        )),
      // 05：窄宽度居中（contentNarrow）——「我的」是设置型页，宽屏下不必拉满。
      // 模型管理 / 运行轨迹等系统子页保持默认宽度（其表格 / 列表需要更宽）。
      // ADR-0088 ticket 02：运行轨迹（全步骤 + 元数据口径）与助手页内的历史会话
      // （气泡口径）并列，入口分离；详情是列表的下钻，返回统一回列表。
      // ticket 08：列表页经由「我的」入栈进入，套返回头使返回落回「我的」。
      RunTracePage() => _withBackHeader(AiRunTraceView(
          onOpenRun: (run) => _go(RunTraceDetailPage(run.id)),
        )),
      RunTraceDetailPage(runId: final runId) => AiRunTraceDetailView(
          runId: runId,
          onBack: _back,
        ),
      StudentDetailPage(studentId: final id, initialTab: final tab) =>
        StudentDetailScreen(
          studentId: id,
          initialTab: tab,
          onBack: _back,
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
          GenerationBanner(
            state: preview,
            onStop: () =>
                ref.read(taskGenNotifierProvider.notifier).stop(),
          ),
        Expanded(child: _buildTeacherPage()),
      ],
    );
  }

  /// 「我的」页内系统分区入栈进入的页面（模型管理 / 运行轨迹）统一套一个返回头：
  /// 左上角「返回」[AppIconAction]，点它走 [_back]（出栈）落回「我的」。
  ///
  /// 这两个页面原本是侧栏根页、自身不带返回按钮；搬进「我的」后必须经此头提供返回，
  /// 否则用户进入后只能靠系统返回键——单一出口原则也要求返回动作集中在组合根。
  Widget _withBackHeader(Widget page) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppIconAction(
                icon: LucideIcons.arrowLeft,
                semanticLabel: '返回',
                onPressed: _back,
              ),
            ),
          ),
          Expanded(child: page),
        ],
      );

  /// 05：把页面内容收进窄宽度框（contentNarrow），两侧不再大片留白。
  ///
  /// 只声明「这个页想要更窄」，实际生效由壳的 [AppContentFrame]（默认 contentWide）
  /// 让内层更紧者生效——页面本身不感知宽窄，也不改动任何内部排版。未包裹的页面沿用
  /// 壳的默认宽度。应用：表单类页面（出题 / 新建·编辑学生）与「我的」。
  Widget _narrow(Widget child) =>
      AppContentFrame(maxWidth: AppLayout.contentNarrow, child: child);

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
    if (state.dataOrNull == null || state.dataOrNull!.isEmpty) return;
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ExportPreviewPage(
          request: const ExportSheetRequest(
            source: 'wrong_book',
            dueOnly: true,
          ),
          title: '今日复习',
          downgradedCount: countDowngradedQuestions(
            stems: state.dataOrNull!.map((e) => e.stem),
            optionLists: state.dataOrNull!.map((e) => e.options),
          ),
        ),
      ),
    );
  }

  // 导航目的地构造器（`teacher_destinations.dart`）：方法体抽出后本文件回到
  // ADR-0058 基线内，新增「资料库」入口不再顶破棘轮。
  NavigationDestinations get _destinations => NavigationDestinations(
        goEntry: _goEntry,
        goChildTab: _switchChildTab,
        goProfile: _onProfileTap,
        genTrailing: _genTrailing,
      );

  /// 学生端主栏：五个槽位常驻在 [IndexedStack] 里，「我的」是第五个槽位。
  ///
  /// ⚠️ 以前 [ChildProfilePage] 走独立分支、把整个 IndexedStack 换掉：看一眼个人信息，四个
  /// 页签的 State 就全部销毁，切回首页要重建、滚动位置全丢。槽位化后只翻转 index，State 全程活着。
  Widget _buildChildView() => IndexedStack(
        index: childPageIndex(_childPage),
        children: [
          StudentHome(
            user: widget.user,
            onNavigateToPractice: _navigateToPractice,
            onNavigateToReview: () => _switchChildTab(1),
            onNavigateToWrongQuestions: () => _switchChildTab(2),
          ),
          ReviewScreen(
            showBack: false,
            // 复习页是页签、不是 push 出来的路由，「返回」只能由壳翻译成切页签。
            onExit: () => _switchChildTab(0),
            onExportDue: _exportDueReviews,
          ),
          const WrongQuestionsScreen(showBack: false),
          StudentMasteryScreen(user: widget.user),
          // 05：学生端「我的」同样用窄宽度居中（contentNarrow）。IndexedStack 始终
          // 挂载全部槽位（保活），该窄框作为槽位内容常驻、仅当前页签可见。
          _narrow(ProfileScreen(user: widget.user, onLogout: widget.onLogout)),
        ],
      );

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

  /// 壳外页面（push 出来的助手整页）请求的跳转：翻成页面后按**换一级入口**处理。
  ///
  /// 助手在壳的页面树之外，一次跳转与教师当前的下钻链没有上下级关系，所以它等同
  /// 于点侧栏：换入口 + 清历史——否则从助手跳到「题库」后按返回会弹回跳转前那一条
  /// 与本题无关的下钻链。
  ///
  /// 无条件注册（不放进 `isTeacher` 分支）：ref.listen 的调用次数在多次 build
  /// 之间必须一致，条件注册会让「角色分支变化」时的订阅数量对不上。
  void _listenShellNavigation() {
    ref.listen(shellNavigationProvider, (_, next) {
      if (next == null) return;
      // 先消费再执行：不清空的话下一次 rebuild 会重复触发同一次跳转。
      ref.read(shellNavigationProvider.notifier).consume();
      final page = _teacherPageFor(next);
      if (page != null) _goEntry(page);
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

    late final Widget shell;
    // 09：侧栏「任务」项的待审核草稿计数（draft + ready）。watch 在壳这一层、跨页常驻，
    // 离开任务页后徽标仍准确——计数来自服务端随任务响应下发的全量快照。
    final draftCount = ref.watch(teacherDraftCountProvider);
    if (widget.user.isTeacher) {
      // ADR-0057 P1：出题在壳这一层 watch，跨 Tab 常驻可见。
      final gen = ref.watch(taskGenNotifierProvider);
      shell = AdaptiveShell(
        mode: AppUserMode.teacher,
        // 05：壳内换页淡入转场以「当前页面」单一事实源驱动；09：紧凑档顶栏显示当前页面名。
        bodyKey: _teacherPage,
        // 09：紧凑档顶栏显示当前页面名（取 01 的单一映射），取代固定的应用名；
        // 下钻页自然显示它自己的名字（_teacherPage 已是栈顶派生）。
        currentTitle: teacherPageFace(_teacherPage).title,
        destinations: _destinations.teacher(
          _teacherPage,
          gen,
          parent: _teacherNav.parent,
          draftCount: draftCount,
        ),
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
    } else {
      shell = AdaptiveShell(
        mode: AppUserMode.student,
        // 05：壳内换页淡入转场以「当前页签」单一事实源驱动（IndexedStack 保活，不重播）。
        bodyKey: _childPage,
        // 09：紧凑档顶栏显示当前页名（学生端未来若启用顶栏亦遵循 01 映射）。
        currentTitle: childPageFace(_childPage).title,
        // 显示个人信息时页签一律取消高亮（槽位 4 不落在任何页签下标上）——否则两个同时亮。
        destinations: _destinations.child(childPageIndex(_childPage)),
        profileDestination:
            _destinations.profile(active: _childPage is ChildProfilePage),
        sidebarBottom: AdaptiveUserBlock(
          user: widget.user,
          onProfileTap: _onProfileTap,
          // 学生年级已改由所属班级承载（ADR-0086 修正）：此处以「分班状态」替代原年级展示。
          subtitle: widget.user.classId != null ? '已分班' : '未分班',
        ),
        body: _buildChildView(),
      );
    }

    // 系统返回键接管（P0-2）：**canPop 恒为 false** —— 全 App 只有一个 route，把
    // 系统返回直接放行等于弹掉根路由（整棵渲染树没了，下一次重建撞 Navigator 的
    // `_history.isNotEmpty` 断言）。每一次系统返回都先落到 [_onSystemBack]：
    // 非根页面 → 壳内回退一步；根页面 → 交回系统退出应用。
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _onSystemBack,
      child: shell,
    );
  }
}
