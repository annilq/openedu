import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_content_frame.dart';
import 'app_top_bar.dart';

/// `Navigator.push` 出来的**整页**：内容框 + 顶栏 + **跑不掉的出路**。
///
/// 存在的理由只有一条：**被 push 的路由不在 [AdaptiveShell] 子树里**，壳给内容区套的
/// 宽度约束、以及壳自己提供的侧栏/底栏导航，它一概拿不到。于是每一页都得自己记住两件事：
/// ① 自己套宽度上限；② 自己给返回入口。这两件事只要有一件忘了，页面就是坏的——
/// 而且**坏了也不会报错**：前者在大屏上悄悄拉宽，后者把人锁死在这一屏
/// （`ExportPreviewPage` 上线时就是漏了 `showBack`，桌面端既无系统返回手势也无 Esc）。
///
/// 因此本组件把「出路」从**每页自觉**改成**结构默认**：
/// - [showBack] 默认 **true**（与裸 AppTopBar 的 false 相反）——想不要必须显式关；
/// - Esc 默认可返回（桌面端的基本礼仪），由内部 [Focus] + Shortcuts 实现。
///
/// 页面仍然可以完全自己撑局面：不传 [title] 就不画顶栏，由 [child] 自带。
class AppPushedPage extends StatelessWidget {
  const AppPushedPage({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.showBack = true,
    this.onBack,
    this.background,
    this.maxWidth = AppLayout.contentWide,
    this.escapeToBack = true,
  });

  /// 顶栏以下的一切。可以是完整的 `Column`（含 `Expanded` 主体 + 底部行动条）。
  final Widget child;

  /// 给了就由本骨架画 [AppTopBar]；不给则页面自己画（完全自定义顶栏时留空）。
  final String? title;

  /// 顶栏右侧那个 40 宽槽位（全站只允许一个图标行动）。
  final Widget? trailing;

  final bool showBack;

  final VoidCallback? onBack;

  /// 页面底色。为 null 时不铺背景，由调用方自己决定（底部要通栏的页面常常不要）。
  final Color? background;

  final double maxWidth;

  /// 关闭 Esc 返回。仅在 Esc 已被页面内层用途占用时才需要（Esc 优先作用于焦点所在的
  /// 内层 Shortcuts，一般不必关）。
  final bool escapeToBack;

  @override
  Widget build(BuildContext context) {
    void leave() {
      final navigator = Navigator.of(context);
      if (onBack != null) {
        onBack!();
        return;
      }
      // maybePop 而非 pop：同一个 Widget 也可能被直接当某个 Navigator 的 home
      // （那种情况没有可 pop 的路由），pop 会抛断言。
      navigator.maybePop();
    }

    final Widget page = AppContentFrame(
      maxWidth: maxWidth,
      child: Column(
        children: [
          if (title != null)
            AppTopBar(
              title: title!,
              showBack: showBack,
              onBack: onBack,
              trailing: trailing,
            ),
          // 用 Expanded 而不是直接塞进去：Column 给**非 flex 孩子**的是竖向无界约束，
          // 页面的 children 里常有 Expanded（主体占满剩余、底部行动条收尾），
          // 无界 + flex 会直接抛 "children have non-zero flex but incoming height
          // constraints are unbounded"。套一层 flex 孩子才能把边界传下去。
          Expanded(child: child),
        ],
      ),
    );

    final framed = background == null
        ? page
        : ColoredBox(color: background!, child: page);

    return escapeToBack
        ? _EscapeToPop(onEscape: leave, child: framed)
        : framed;
  }
}

/// Esc → 离开本页。
///
/// 两处不显然的地方：
/// - **Shortcuts 必须是焦点节点的祖先**。键事件只向上冒泡，不会向下派发：写成
///   `Focus(child: Shortcuts(...))` 就永远收不到键。
/// - **必须 autofocus**。桌面端刚进页面时焦点树里往往什么都没有，没有焦点节点
///   就没有事件来源，Esc 会是死的。内层控件拿到焦点后，事件照样会冒泡经过这里。
class _EscapeToPop extends StatelessWidget {
  const _EscapeToPop({required this.onEscape, required this.child});

  final VoidCallback onEscape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _LeaveIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _LeaveIntent: CallbackAction<_LeaveIntent>(
            onInvoke: (_) {
              onEscape();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          // 这个节点没有外观，也不该出现在 Tab 遍历里。
          skipTraversal: true,
          child: child,
        ),
      ),
    );
  }
}

class _LeaveIntent extends Intent {
  const _LeaveIntent();
}
