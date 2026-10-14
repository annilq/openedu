import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 壳内换页的淡入转场（nav-ia-review ticket 05）。
///
/// 两套观感必须一致、不得并存两套动画语言（验收）：壳内切页与 push 整页都用「轻微
/// 淡入」。push 走 [CupertinoPageRoute] 自有转场，本组件只管壳内 body 的换页，两者
/// 互不干扰。
///
/// 两档实现：
/// - 教师端（body 是单一页面 widget，每次换页都重建）：用 [AnimatedSwitcher] 以
///   [pageKey] 区分新旧页，交叉淡入淡出。教师页不需要跨换页保活（本来每次切页都
///   重建），直接换挂即可，旧页在淡出期间仍挂载、淡完即卸载。
/// - 学生端（body 是常驻 [IndexedStack]，五个页签全部挂载以保持各自 State）：
///   绝不能用 [AnimatedSwitcher] 换挂——那会把整个 [IndexedStack] 卸载重建、丢掉其它
///   页签的滚动位置与取数状态（ticket 04 的槽位化正是为了避免这点）。改为
///   [_KeepAliveFade]：IndexedStack 始终挂载，只在 [pageKey]（当前页签）变化时把整棵
///   内容「脉冲」淡入一次。
///
/// reduce-motion：时长显式归零（ADR-0044），不靠隐式动画的缺省行为。
class ShellBodyTransition extends StatelessWidget {
  final Object? pageKey;
  final AppUserMode mode;
  final Widget child;

  const ShellBodyTransition({
    super.key,
    required this.pageKey,
    required this.mode,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // 未声明 pageKey（既有测试 / 降级路径）：不加任何转场，零行为变化。
    if (pageKey == null) return child;

    if (mode == AppUserMode.student) {
      return _KeepAliveFade(tabKey: pageKey, child: child);
    }

    // 教师端：pageKey 即 [_teacherPage]（sealed + const 构造 → 规范实例，身份即等价）。
    // 每次换页走 cross-fade。
    return AnimatedSwitcher(
      duration: reducedMotionOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(pageKey), child: child),
    );
  }
}

/// 学生端壳内 body 的「脉冲淡入」：保留 [IndexedStack] 常驻挂载，仅在当前页签变化时
/// 把内容淡入一次（≤150ms）。
///
/// 为什么不是 [AnimatedSwitcher]：学生端 body 是五个页签共享的 [IndexedStack]，一旦
/// 换挂旧的会卸载、State 全丢（ticket 04 的槽位化正是为了避免这点）。这里让 child
/// 恒为同一个 [IndexedStack]（Flutter 按类型 / 位置复用其 element，State 不丢），只靠
/// [AnimationController] 在 [tabKey] 变化时播放一次 0→1 的透明度脉冲。
class _KeepAliveFade extends StatefulWidget {
  final Object? tabKey;
  final Widget child;

  const _KeepAliveFade({required this.tabKey, required this.child});

  @override
  State<_KeepAliveFade> createState() => _KeepAliveFadeState();
}

class _KeepAliveFadeState extends State<_KeepAliveFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );

  @override
  void initState() {
    super.initState();
    // 首帧已在正确页签，不淡入（opacity = 1）。时长初值取 150ms；真正的
    // reduce-motion 归零在 [didChangeDependencies] 里读 MediaQuery 后设置——initState
    // 内禁止依赖 inherited widget。
    _ctrl.value = 1;
  }

  void _syncDuration() {
    _ctrl.duration = reducedMotionOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDuration();
  }

  @override
  void didUpdateWidget(covariant _KeepAliveFade old) {
    super.didUpdateWidget(old);
    // 仅当当前页签真正变化时才脉冲。child（IndexedStack）实例每次 build 都不同但槽位
    // 不变时不应重播动画；_childPage 由 childPageFromIndex 返回 const 规范实例，身份即
    // 等价（tabKey 不变 = 没换页签）。
    if (old.tabKey != widget.tabKey) {
      _syncDuration();
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _ctrl, child: widget.child);
}
