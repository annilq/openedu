import 'package:flutter/widgets.dart';

import '../../../../shared/widgets/adaptive_shell.dart';
import '../page_labels.dart';
import '../teacher_pages.dart';
import '../child_pages.dart';
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
      _item(const OverviewPage(), active: active is OverviewPage),
      // 发布任务已收进任务页（方案 A）：生成页是任务页的一个动作态，不再单列侧栏。
      // 故它高亮时「任务」也亮；出题中点按即回生成页（ADR-0057 P1）。
      _item(
        const TaskListPage(),
        active: active is TaskListPage || active is CreateTaskPage,
        to: gen is TaskGenPreview && gen.streaming
            ? const CreateTaskPage()
            : const TaskListPage(),
        // ADR-0057 P1：出题进度徽标从「布置任务」迁到「任务」项。
        trailing: genTrailing(gen),
      ),
      _item(const StudentManagementPage(),
          active: active is StudentManagementPage),
      _item(const ClassManagementPage(), active: active is ClassManagementPage),
      _item(const QuestionBankPage(), active: active is QuestionBankPage),
      _item(const MaterialLibraryPage(), active: active is MaterialLibraryPage),
      _item(const ModelsPage(), active: active is ModelsPage),
      // ADR-0088 ticket 02：运行轨迹（审计 / 排障口径）独立入口——与助手页内的
      // 「历史会话」（气泡口径）并列，不混入同一个页面。
      _item(const RunTracePage(),
          active: active is RunTracePage || active is RunTraceDetailPage),
      _item(const CoursewarePage(), active: active is CoursewarePage),
      _item(
        const SceneLibraryPage(),
        // 详情页高亮列表页：详情是列表的下钻，不是一个独立入口，否则点了某个
        // 场景后侧栏会「谁都不亮」，教师以为自己离开了导航。
        active: active is SceneLibraryPage || active is SceneLibraryDetailPage,
      ),
      _item(const AssetLibraryPage(), active: active is AssetLibraryPage),
    ];
  }

  /// 学生端页签目的地。AI 入口统一走右下角浮球（ADR-0036 / 0047），不再单列页签。
  List<AdaptiveNavDestination> child(int activeIndex) => [
        _tab(const ChildHomePage(), activeIndex),
        _tab(const ChildReviewPage(), activeIndex),
        _tab(const ChildWrongQuestionsPage(), activeIndex),
        _tab(const ChildMasteryPage(), activeIndex),
      ];

  /// 「我的」目的地。教师端与页面共用同一个状态；学生端在显示个人信息时
  /// 由调用方传 active=false，避免页签与「我的」同时高亮。
  AdaptiveNavDestination profile({required bool active}) {
    // 「我的」对两个角色是同一个入口、同一份文案，映射表里也刻意只有一个常量
    // （ticket 01）——这里取教师端分支作为它的出口。
    final face = teacherPageFace(const ProfilePage());
    return AdaptiveNavDestination(
      icon: face.icon,
      label: face.title,
      active: active,
      onTap: goProfile,
    );
  }

  /// 目的地 = 目标页 + 是否高亮；标题与图标一律从 `page_labels.dart` 的单一映射取
  /// （ticket 01），本文件不再存第二份文案——两处并存时改名票（07）改一处漏一处，
  /// 界面会同时冒出两个名字。
  ///
  /// [to] 用于「点了这一项却落在别的页面」的唯一情形：出题中点「任务」回生成页
  /// （ADR-0057 P1），此时侧栏显示的仍是「任务」，不是生成页自己的标题。
  AdaptiveNavDestination _item(
    TeacherPage page, {
    required bool active,
    TeacherPage? to,
    Widget? trailing,
  }) {
    final face = teacherPageFace(page);
    return AdaptiveNavDestination(
      icon: face.icon,
      label: face.title,
      active: active,
      onTap: () => goEntry(to ?? page),
      trailing: trailing,
    );
  }

  /// 学生端页签：下标走 [childPageIndex] 而不是在这里重排一份序号——「页签下标」
  /// 与「页面类型」是同一个事实的两面（ADR-0059），排两份就会不同步。
  AdaptiveNavDestination _tab(ChildPage page, int activeIndex) {
    final face = childPageFace(page);
    final index = childPageIndex(page);
    return AdaptiveNavDestination(
      icon: face.icon,
      label: face.title,
      active: activeIndex == index,
      onTap: () => goChildTab(index),
    );
  }
}
