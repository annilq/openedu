import 'teacher_pages.dart';

/// 教师端导航历史栈（ADR-0059 / ticket 03 P1-3）。
///
/// **「当前页面」只有一个状态：栈顶**（[current]）。栈不是与「当前页面」并列的
/// 第二个真源，而是它的历史——ADR-0059 要防的正是这个：历史上「侧栏索引 + 覆盖层
/// + `_showProfile` 布尔」三份并列状态各自记得清理，漏清一个就出现「点了『我的』
/// 但个人信息根本没进渲染树」。收成一份之后，改页面只有 [push] / [reset] / [pop]
/// 三条路，**没有任何一条能让「当前页面」与「历史」说不一致的话**。
///
/// 「根」只有一个含义：**概览**（[OverviewPage]）。栈底恒为概览，所以 [canPop]
/// 为假 ⟺ 当前就在概览——返回键在那里**不消费**，交回系统退出应用（P0-2）。
///
/// 为什么 [reset] 之后栈里会有两页（概览 + 新入口）：换一级入口清的是**上一个入口
/// 的下钻历史**，不是「概览」这个根。切到「题库」后按返回回概览、而不是弹回上一次
/// 的班内学生页；再按一次才交回系统。
class TeacherNavStack {
  TeacherNavStack() : _stack = <TeacherPage>[const OverviewPage()];

  /// 栈底恒为 [OverviewPage]；[reset] / [pop] 都不会把它弹掉。
  final List<TeacherPage> _stack;

  /// 当前页面 = 栈顶。**这是唯一的事实源**，不是栈之外的另一个字段。
  TeacherPage get current => _stack.last;

  /// 当前页面的上一层（来源页）；已在根页面时返回 null。
  ///
  /// 草稿审核页的侧栏高亮靠它：审核不是一个侧栏入口，而是「从哪一页点进来就属于
  /// 哪一页」的延续。以前这个关系由每个调用方手工填 `back` 字段，漏填就静默回落
  /// 概览且 `flutter analyze` 照不出来。
  TeacherPage? get parent => _stack.length > 1 ? _stack[_stack.length - 2] : null;

  /// 还能不能往回退：为假表示当前就在根页面（概览），返回键应交回系统。
  bool get canPop => _stack.length > 1;

  /// **下钻**：入栈。新增下钻页**零义务**——不需要声明回落目标，退回哪儿由历史决定。
  void push(TeacherPage page) => _stack.add(page);

  /// **切换一级入口**：替换当前页面并清空历史。
  ///
  /// 侧栏点「题库」、点「我的」、助手卡片跳转都属于这一档：它们是**换入口**，不是
  /// 从当前页往下钻，所以上一个入口的下钻链必须一并丢弃——否则切到题库后按返回会
  /// 跨入口弹回上一次的班内学生页。
  void reset(TeacherPage page) {
    _stack
      ..clear()
      ..add(const OverviewPage());
    if (page is! OverviewPage) _stack.add(page);
  }

  /// **回退一步**：出栈并返回新的当前页；已在根页面时返回 null 且不动栈。
  TeacherPage? pop() {
    if (!canPop) return null;
    _stack.removeLast();
    return _stack.last;
  }
}
