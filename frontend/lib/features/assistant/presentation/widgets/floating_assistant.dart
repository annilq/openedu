import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../screens/assistant_chat_page.dart';

/// 家长端 AI 助手宿主（ADR-0036 单入口 / ADR-0047 整页形态）。
///
/// 把 [child]（HomeScreen）铺底、右下角叠一个常驻**浮动按钮**；点击后 push 整页
/// [AssistantChatPage]——助手是**单独页面**，不再是与宿主布局无关的浮层。
///
/// **为什么从浮层改成整页**：浮层尺寸（380×540）与导航壳（侧栏 + `contentWide`
/// 内容列）没有任何关系，桌面 / 平板下它压在内容上，既不齐侧栏也不齐内容列，看起来
/// 像贴纸。整页形态则与娃娃端「问 AI 老师」页签是**同一个页面、同一份会话、同一套
/// 渲染**，宽度随可用空间自然适配（ADR-0045）。
///
/// 入口仍然只有这一个浮动按钮（ADR-0036：每个角色恰好一个 AI 入口）。按钮不在助手
/// 页上重复出现——整页自带返回，浮球盖在整页右下角会正好压住输入栏。
class FloatingAssistant extends StatelessWidget {
  final Widget child;

  const FloatingAssistant({super.key, required this.child});

  void _open(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        // showBack：整页自带返回（push 路由，默认走 Navigator.maybePop）。
        // isParent：标题与空态引导按家长口径渲染——家长能出题 / 查任务，
        // 与娃娃端「只讲学习内容」的边界不同。
        builder: (_) => const AssistantChatPage(showBack: true, isParent: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: AssistantLauncher(onTap: () => _open(context)),
        ),
      ],
    );
  }
}

/// 助手浮动入口按钮：新粗野圆形强调件（`primary` 底 + 墨黑描边 + 硬阴影）。
///
/// 收敛前它是裸 `GestureDetector`——**不在焦点树里**（桌面端 Tab 跳不过来、
/// Enter 点不动，而 `flutter analyze` 照不出来，ADR-0045/0046）。现在走
/// [AppFocusableAction]，按压反馈与 [AppCard] 同一套语义：整块下沉 + 硬阴影收拢。
class AssistantLauncher extends StatefulWidget {
  final VoidCallback onTap;

  const AssistantLauncher({super.key, required this.onTap});

  @override
  State<AssistantLauncher> createState() => _AssistantLauncherState();
}

class _AssistantLauncherState extends State<AssistantLauncher> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    // 暗模式下墨黑硬阴影与背景同色、不可见 → 退化为无阴影（ADR-0044）。
    final dark = scheme.brightness == Brightness.dark;

    return AppFocusableAction(
      onTap: widget.onTap,
      semanticLabel: 'AI 学习助手',
      borderRadius: BorderRadius.circular(AppLayout.tapTargetLg / 2),
      onPressedChanged: (pressed) => setState(() => _pressed = pressed),
      // 只动 transform（GPU 合成），不触发布局重排。
      child: Transform.translate(
        offset: _pressed ? AppElevation.offsetPressed : Offset.zero,
        child: Container(
          width: AppLayout.tapTargetLg,
          height: AppLayout.tapTargetLg,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
            border: Border.all(
                color: AppBrutal.ink, width: AppElevation.borderWidth),
            boxShadow: dark
                ? AppElevation.none
                : (_pressed
                    ? AppElevation.hardPressed()
                    : AppElevation.hard()),
          ),
          child: Icon(
            LucideIcons.bot,
            color: scheme.onPrimary,
            size: 24,
          ),
        ),
      ),
    );
  }
}
