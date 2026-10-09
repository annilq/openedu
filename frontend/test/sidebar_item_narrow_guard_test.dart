// 回归守卫：折叠/展开动画途中，[SidebarCollapseScope.collapsed] 布尔量瞬间翻转为
// false，但侧栏宽度是连续动画的（AdaptiveShell 的 AnimatedContainer 64↔240）。
// 修复前此时展开 Row 会被塞进仍很窄的容器 → 横向溢出（RenderFlex overflow）。
// 本测试断言：即便 collapsed=false，只要实际可用宽度低于阈值，项仍按 collapsed
// （仅图标）渲染且不溢出。
//
// 注意：不能用 CupertinoApp/ShadApp 包 home 后靠 SizedBox 约束宽度——其 home 走
// Navigator 路由被撑满视口，SizedBox 约束在 home 子树内失效（见
// adaptive_shell_layout_test 第 32-33 行注释）。这里改用 ProviderScope + Directionality
// 直接挂载（与 adaptive_shell_layout_test 同款 harness），SizedBox 才能正确约束。
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/widgets/app_sidebar.dart'
    show AppSidebarItem, SidebarCollapseScope;

void main() {
  Widget host(Widget child) => ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: child,
        ),
      );

  testWidgets('窄容器内 collapsed=false 仍按 collapsed 渲染且不溢出',
      (tester) async {
    // setSurfaceSize 把整个视口压窄（SizedBox 在该 harness 下约束失效，见文件头注释），
    // 模拟展开动画初期 AnimatedContainer 仍很窄的真实宽度。
    await tester.binding.setSurfaceSize(const Size(50, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        SidebarCollapseScope(
          // 即便意图是「展开」，窄容器也必须落地为 collapsed 布局。
          collapsed: false,
          onToggle: () {},
          child: AppSidebarItem(
            icon: LucideIcons.house,
            label: '首页',
            active: true,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 关键：不得抛 RenderFlex 横向溢出。
    expect(tester.takeException(), isNull);
    // collapsed 布局隐藏 label、只渲染图标。
    expect(find.text('首页'), findsNothing);
    expect(find.byIcon(LucideIcons.house), findsOneWidget);
  });

  testWidgets('充足宽度下 collapsed=false 正常渲染展开行（label 可见）',
      (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 240,
          child: SidebarCollapseScope(
            collapsed: false,
            onToggle: () {},
            child: AppSidebarItem(
              icon: LucideIcons.house,
              label: '首页',
              active: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('首页'), findsOneWidget);
  });
}
