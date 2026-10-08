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
    required this.go,
    required this.goChildTab,
    required this.goProfile,
    required this.genTrailing,
  });

  /// 教师端统一导航出口（`HomeScreen._go`）。
  final void Function(TeacherPage page) go;

  /// 学生端页签切换（`HomeScreen._switchChildTab`）。
  final void Function(int index) goChildTab;

  /// 「我的」入口（`HomeScreen._onProfileTap`）。
  final VoidCallback goProfile;

  /// 出题进度徽标（依赖 context 的渲染留在组合根）。
  final Widget? Function(TaskGenState gen) genTrailing;

  /// 教师端侧栏目的地：与旧 TeacherSidebar 同序（概览/任务/布置/错题/答疑/
  /// 题库/资料库/模型）。审核页高亮「进来时的那一页」——审核是任务的延续，
  /// 不是一个新的侧栏入口，故 active 取 `highlightFor(page)`。
  List<AdaptiveNavDestination> teacher(TeacherPage page, TaskGenState gen) {
    final active = highlightFor(page);
    return [
      AdaptiveNavDestination(
          icon: LucideIcons.layoutDashboard,
          label: '概览',
          active: active is OverviewPage,
          onTap: () => go(const OverviewPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.listTodo,
          label: '任务',
          active: active is TaskListPage,
          onTap: () => go(const TaskListPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.pencil,
          label: '布置任务',
          active: active is CreateTaskPage,
          onTap: () => go(const CreateTaskPage()),
          // ADR-0057 P1：出题进行中在侧栏也亮一个进度徽标，点它即回生成页。
          trailing: genTrailing(gen)),
      AdaptiveNavDestination(
          icon: LucideIcons.users,
          label: '学生',
          active: active is StudentManagementPage,
          onTap: () => go(const StudentManagementPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.library,
          label: '题库',
          active: active is QuestionBankPage,
          onTap: () => go(const QuestionBankPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.folderOpen,
          label: '资料库',
          active: active is MaterialLibraryPage,
          onTap: () => go(const MaterialLibraryPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.cpu,
          label: '模型管理',
          active: active is ModelsPage,
          onTap: () => go(const ModelsPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.bookOpen,
          label: '课件',
          active: active is CoursewarePage,
          onTap: () => go(const CoursewarePage())),
      AdaptiveNavDestination(
          icon: LucideIcons.component,
          label: '场景库',
          // 详情页高亮列表页：详情是列表的下钻，不是一个独立入口，否则点了某个
          // 场景后侧栏会「谁都不亮」，教师以为自己离开了导航。
          active: active is SceneLibraryPage || active is SceneLibraryDetailPage,
          onTap: () => go(const SceneLibraryPage())),
      AdaptiveNavDestination(
          icon: LucideIcons.images,
          label: '素材库',
          active: active is AssetLibraryPage,
          onTap: () => go(const AssetLibraryPage())),
    ];
  }

  /// 学生端页签目的地。
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
            icon: LucideIcons.sparkles,
            label: '问 AI 老师',
            active: activeIndex == 3,
            onTap: () => goChildTab(3)),
        AdaptiveNavDestination(
            icon: LucideIcons.target,
            label: '掌握度',
            active: activeIndex == 4,
            onTap: () => goChildTab(4)),
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
