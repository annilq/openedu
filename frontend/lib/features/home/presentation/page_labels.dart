import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'child_pages.dart';
import 'teacher_pages.dart';

/// 页面 → 门面（标题 + 图标）的**唯一**映射表（ticket 01）。
///
/// 「门面」= 侧栏项、紧凑档顶栏、将来的路径恢复各自需要的那两个值。搬移前它们散在
/// `teacher_destinations.dart` 的目的地构造器里，且只有 11 个一级入口有，下钻页一个
/// 都没有——同一份文案于是有了两个候选落点：菜单，以及将来接顶栏与路径恢复的那一票。
///
/// 放在 `features/home/presentation/` 而不是 `shared/utils/`：映射的输入类型
/// [TeacherPage] / [ChildPage] 住在 features，`shared/` 不许 import `features/`
/// （ADR-0037，守卫 `test/feature_boundaries_test.dart`）。这也是它与先例
/// `shared/utils/question_labels.dart` 的区别——那份收的是后端字符串枚举，
/// 这份收的是页面类型，只能跟着页面类型走。
///
/// 两个 switch 都穷尽匹配（`sealed` 保证），且**故意不写 `_ =>` 兜底**：新增页面
/// 忘记登记 → 编译失败，而不是运行时显示空白。给它们塞一个
/// `_ => (title: '', icon: ...)` 会悄悄废掉这个保护，守卫见
/// `test/page_labels_test.dart`。
///
/// ⚠️ 本票是纯搬移：一级入口的文案逐字照抄搬移前的菜单，不改名、不调序。
/// 改名（资料库 → 备课资料 等）是 07 的活，届时只改这里。
const _profileFace = (title: '我的', icon: LucideIcons.userRound);

/// 教师端页面 → 门面。
///
/// 下钻页此前没有存档点，这里按**它自己的口径**补上（「编辑学生」而不是父级的
/// 「学生」），供顶栏与路径恢复使用（09 / 12）。
({String title, IconData icon}) teacherPageFace(TeacherPage page) => switch (page) {
      OverviewPage() => (title: '概览', icon: LucideIcons.layoutDashboard),
      CreateTaskPage() => (title: '发布任务', icon: LucideIcons.listTodo),
      TaskListPage() => (title: '任务', icon: LucideIcons.listTodo),
      AddStudentPage() => (title: '添加学生', icon: LucideIcons.userPlus),
      EditStudentPage() => (title: '编辑学生', icon: LucideIcons.userRoundPen),
      QuestionBankPage() => (title: '题库', icon: LucideIcons.library),
      MaterialLibraryPage() => (title: '备课资料', icon: LucideIcons.folderOpen),
      ModelsPage() => (title: '模型管理', icon: LucideIcons.cpu),
      TaskReviewPage() => (title: '草稿审核', icon: LucideIcons.clipboardCheck),
      ProfilePage() => _profileFace,
      StudentManagementPage() => (title: '学生', icon: LucideIcons.users),
      StudentDetailPage() => (title: '学生详情', icon: LucideIcons.userRound),
      CoursewarePage() => (title: '课件', icon: LucideIcons.bookOpen),
      SceneLibraryPage() => (title: '场景库', icon: LucideIcons.component),
      SceneLibraryDetailPage() => (title: '场景库详情', icon: LucideIcons.puzzle),
      SceneLibraryEditorPage() => (title: '场景编辑器', icon: LucideIcons.penTool),
      AssetLibraryPage() => (title: '图片素材', icon: LucideIcons.images),
      ClassManagementPage() => (title: '班级管理', icon: LucideIcons.school),
      // 下钻页的标题就是它自己的班级名——由入参直传（ADR-0086，避免看着 A 班却显示
      // B 班），页面上显示什么这里就跟着显示什么，不写死通用名。
      ClassStudentsPage(:final className) =>
        (title: className, icon: LucideIcons.usersRound),
      RunTracePage() => (title: '运行轨迹', icon: LucideIcons.route),
      RunTraceDetailPage() => (title: '运行轨迹详情', icon: LucideIcons.scrollText),
    };

/// 学生端页面 → 门面。与 [teacherPageFace] 同构：四个页签标题此前也写在
/// `NavigationDestinations.child()` 里，一并收口到同一处。
({String title, IconData icon}) childPageFace(ChildPage page) => switch (page) {
      ChildHomePage() => (title: '首页', icon: LucideIcons.house),
      ChildReviewPage() => (title: '复习', icon: LucideIcons.refreshCw),
      ChildWrongQuestionsPage() => (title: '错题本', icon: LucideIcons.bookOpen),
      ChildMasteryPage() => (title: '掌握度', icon: LucideIcons.target),
      // 「我的」两个角色共用同一份门面——取 [_profileFace]，避免同一份文案在两个
      // switch 里各写一遍。
      ChildProfilePage() => _profileFace,
    };
