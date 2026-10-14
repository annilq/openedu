import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/widgets/adaptive_shell.dart';
import '../teacher_pages.dart';
import '../providers/home_notifier.dart';

/// 导航目的地构造器（从 `home_screen.dart` 抽出，ADR-0058 棘轮）。
///
/// 纯粹的「值进 → 目的地列表出」：导航动作以回调注入，本类不认识
/// `HomeScreen` 的状态，壳层状态机（ADR-0059）仍只活在组合根里。
class NavigationDestinations {
  const NavigationDestinations({
    required this.goEntry,
    required this.goChildTab,
    required this.goProfile,
    required this.genTrailing,
  });

  /// 教师端**切换一级入口**的出口（`HomeScreen._goEntry`）。
  ///
  /// 叫 `goEntry` 而不叫 `go` 是有意的：侧栏每一项都是一级入口，点它是**换入口**——
  /// 清空历史；而壳内下钻（班级 → 班内学生 → 学生详情）是另一条出口（`_go`，入栈）。
  /// 两者混用会让「切到题库后按返回先弹回上一次的班内学生页」。
  final void Function(TeacherPage page) goEntry;

  /// 学生端页签切换（`HomeScreen._switchChildTab`）。
  final void Function(int index) goChildTab;

  /// 「我的」入口（`HomeScreen._onProfileTap`）。
  final VoidCallback goProfile;

  /// 出题进度徽标（依赖 context 的渲染留在组合根）。
  final Widget? Function(TaskGenState gen) genTrailing;

  /// 教师端侧栏目的地：与旧 TeacherSidebar 同序（概览/任务/布置/错题/答疑/
  /// 题库/资料库/模型）。审核页高亮「进来时的那一页」——审核是任务的延续，
  /// 不是一个新的侧栏入口，故 active 取 `highlightFor(page)`。
  ///
  /// [parent] 是历史栈里当前页的上一层，只用于草稿审核页的高亮（审核不是一个侧栏
  /// 入口，高亮它进来时的那一页）；其余页面忽略它。
  List<AdaptiveNavDestination> teacher(
    TeacherPage page,
    TaskGenState gen, {
    TeacherPage? parent,
  }) {
    final active = highlightFor(page, parent: parent);
    return [
      AdaptiveNavDestination(
          icon: LucideIcons.layoutDashboard,
          label: '概览',
          active: active is OverviewPage,
          onTap: () => goEntry(const OverviewPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.listTodo,
          label: '任务',
          // 发布任务已收进任务页（方案 A）：生成页是任务页的一个动作态，不再单列侧栏。
          // 故它高亮时「任务」也亮；出题中点按即回生成页（ADR-0057 P1）。
          active: active is TaskListPage || active is CreateTaskPage,
          onTap: () => gen is TaskGenPreview && gen.streaming
              ? goEntry(const CreateTaskPage())
              : goEntry(const TaskListPage()),
          // ADR-0057 P1：出题进度徽标从「布置任务」迁到「任务」项。
          trailing: genTrailing(gen)),
      AdaptiveNavDestination(
          icon: LucideIcons.users,
          label: '学生',
          active: active is StudentManagementPage,
          onTap: () => goEntry(const StudentManagementPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.school,
          label: '班级管理',
          active: active is ClassManagementPage,
          onTap: () => goEntry(const ClassManagementPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.library,
          label: '题库',
          active: active is QuestionBankPage,
          onTap: () => goEntry(const QuestionBankPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.folderOpen,
          label: '资料库',
          active: active is MaterialLibraryPage,
          onTap: () => goEntry(const MaterialLibraryPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.cpu,
          label: '模型管理',
          active: active is ModelsPage,
          onTap: () => goEntry(const ModelsPage())),
      // ADR-0088 ticket 02：运行轨迹（审计 / 排障口径）独立入口——与助手页内的
      // 「历史会话」（气泡口径）并列，不混入同一个页面。
      AdaptiveNavDestination(
          icon: LucideIcons.route,
          label: '运行轨迹',
          active: active is RunTracePage || active is RunTraceDetailPage,
          onTap: () => goEntry(const RunTracePage())),
      AdaptiveNavDestination(
          icon: LucideIcons.bookOpen,
          label: '课件',
          active: active is CoursewarePage,
          onTap: () => goEntry(const CoursewarePage())),
      AdaptiveNavDestination(
          icon: LucideIcons.component,
          label: '场景库',
          // 详情页高亮列表页：详情是列表的下钻，不是一个独立入口，否则点了某个
          // 场景后侧栏会「谁都不亮」，教师以为自己离开了导航。
          active: active is SceneLibraryPage || active is SceneLibraryDetailPage,
          onTap: () => goEntry(const SceneLibraryPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.images,
          label: '素材库',
          active: active is AssetLibraryPage,
          onTap: () => goEntry(const AssetLibraryPage())),
    ];
  }

  /// 学生端页签目的地。AI 入口统一走右下角浮球（ADR-0036 / 0047），不再单列页签。
  List<AdaptiveNavDestination> child(int activeIndex) => [
        AdaptiveNavDestination(
            icon: LucideIcons.house,
            label: '首页',
            active: activeIndex == 0,
            onTap: () => goChildTab(0)),
        AdaptiveNavDestination(
            icon: LucideIcons.refreshCw,
            label: '复习',
            active: activeIndex == 1,
            onTap: () => goChildTab(1)),
        AdaptiveNavDestination(
            icon: LucideIcons.bookOpen,
            label: '错题本',
            active: activeIndex == 2,
            onTap: () => goChildTab(2)),
        AdaptiveNavDestination(
            icon: LucideIcons.target,
            label: '掌握度',
            active: activeIndex == 3,
            onTap: () => goChildTab(3)),
      ];

  /// 「我的」目的地。教师端与页面共用同一个状态；学生端在显示个人信息时
  /// 由调用方传 active=false，避免页签与「我的」同时高亮。
  AdaptiveNavDestination profile({required bool active}) =>
      AdaptiveNavDestination(
        icon: LucideIcons.userRound,
        label: '我的',
        active: active,
        onTap: goProfile,
      );
}
