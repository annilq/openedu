// 学生端底栏窄屏适配（REPORT P2-4 / ticket 06）的行为契约：
//   1. 窄屏（< AppLayout.bottomNavNarrowMax）五个入口的文字不被省略号截断；
//   2. 五个入口的命中区不小于 AppLayout.tapTarget；
//   3. 常规屏（≥ 阈值）仍是等分排布（纯回归，逐像素不动）；
//   4. 可用宽度物理上放不下 5 个命中区时降级为只留图标，且不横向溢出。
//
// 档位判定只依据 LayoutBuilder 的可用宽度，因此必须用 setSurfaceSize 改视口
// （SizedBox 给不了比 800×600 更宽的视口，会把断点静默测错档）。
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/adaptive_bottom_nav.dart';
import 'package:kids_learn/shared/widgets/adaptive_shell.dart' show AdaptiveShell;
import 'package:kids_learn/shared/widgets/nav_section.dart'
    show AdaptiveNavDestination, SidebarSection;
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';

void main() {
  const labels = <String>['首页', '复习', '错题本', '掌握度', '我的'];

  List<AdaptiveNavDestination> items() => [
        const AdaptiveNavDestination(
            icon: LucideIcons.house, label: '首页', active: true),
        const AdaptiveNavDestination(
            icon: LucideIcons.refreshCw, label: '复习', active: false),
        const AdaptiveNavDestination(
            icon: LucideIcons.bookOpen, label: '错题本', active: false),
        const AdaptiveNavDestination(
            icon: LucideIcons.target, label: '掌握度', active: false),
        const AdaptiveNavDestination(
            icon: LucideIcons.userRound, label: '我的', active: false),
      ];

  /// 直接挂载底栏：[AdaptiveBottomNav] 自带 LayoutBuilder，视口宽度即它的可用宽度。
  Future<void> pumpNav(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        // 学生端排版（labelSmall 走 child 档 13px），与运行时一致。
        child: UserModeScope(
          mode: AppUserMode.student,
          child: AdaptiveBottomNav(items: items()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 独立算出「这段文字排一行需要多宽」——不复用被测组件的任何布局结果。
  ///
  /// RenderParagraph 的宽度 = min(自然宽度, 可用宽度)，所以「渲染宽度 == 自然宽度」
  /// 等价于「没有触发 ellipsis」；被压窄时二者必然不等。
  double naturalWidth(WidgetTester tester, String label) {
    final text = tester.widget<Text>(find.text(label));
    final tp = TextPainter(
      text: TextSpan(text: text.data, style: text.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  /// 五个入口的命中区尺寸（[AppFocusableAction] 就是可点/可聚焦区域本身）。
  List<Size> tapSizes(WidgetTester tester) => tester
      .widgetList<AppFocusableAction>(find.byType(AppFocusableAction))
      .map((w) => tester.getSize(find.byWidget(w)))
      .toList();

  testWidgets('窄屏下五个入口的文字都不被省略号截断', (tester) async {
    await pumpNav(tester, 320);

    for (final label in labels) {
      final rendered = tester.getSize(find.text(label)).width;
      expect(rendered, closeTo(naturalWidth(tester, label), 0.5),
          reason: '320px 下「$label」必须完整显示：等分硬塞会把它压成省略号');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏下五个入口的命中区不小于最小可点尺寸', (tester) async {
    await pumpNav(tester, 320);

    final sizes = tapSizes(tester);
    expect(sizes.length, labels.length);
    for (final size in sizes) {
      expect(size.width, greaterThanOrEqualTo(AppLayout.tapTarget));
      expect(size.height, greaterThanOrEqualTo(AppLayout.tapTarget));
    }
  });

  testWidgets('常规屏（360）仍是等分排布，与现状一致', (tester) async {
    await pumpNav(tester, 360);

    final sizes = tapSizes(tester);
    expect(sizes.length, labels.length);
    for (var i = 0; i < sizes.length; i++) {
      expect(sizes[i].width, closeTo(360 / labels.length, 0.5),
          reason: '第 $i 项在常规宽度下必须仍按 1/5 等分');
      // 等分下每项的左缘就是 i * 份额。
      expect(
        tester
            .getTopLeft(find.byWidget(tester.widgetList<AppFocusableAction>(
                find.byType(AppFocusableAction)).elementAt(i)))
            .dx,
        closeTo(i * 360 / labels.length, 0.5),
      );
    }
    for (final label in labels) {
      expect(tester.getSize(find.text(label)).width,
          closeTo(naturalWidth(tester, label), 0.5));
    }
  });

  testWidgets('放不下 5 个命中区时降级为只留图标，且不溢出', (tester) async {
    // 180 < 5 * tapTarget：五个 44 宽的命中区在物理上放不进 180，此时宁可隐藏
    // 文字也不能让文字被截断或让整行溢出。
    await pumpNav(tester, 180);

    for (final label in labels) {
      expect(find.text(label), findsNothing,
          reason: '极窄档只留图标，$label 的文字不应进入渲染树');
    }
    expect(find.byIcon(LucideIcons.bookOpen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '极窄档不得出现 RenderFlex 溢出');
  });

  testWidgets('窄屏下选中态语言不变（accent 图标 + 加重文字）', (tester) async {
    await pumpNav(tester, 320);

    final scheme = AppTheme.colorsOf(
        tester.element(find.byType(AdaptiveBottomNav)));
    final active = tester.widget<Icon>(find.byIcon(LucideIcons.house));
    expect(active.color, scheme.accent);
    final inactive = tester.widget<Icon>(find.byIcon(LucideIcons.bookOpen));
    expect(inactive.color, scheme.onSurfaceVariant);
    expect(tester.widget<Text>(find.text('首页')).style?.fontWeight,
        FontWeight.w600);
    expect(tester.widget<Text>(find.text('错题本')).style?.fontWeight,
        FontWeight.w500);
  });

  testWidgets('学生端壳在窄屏下把五个入口都挂到底栏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: UserModeScope(
            mode: AppUserMode.student,
            child: AdaptiveShell(
              mode: AppUserMode.student,
              destinations: [SidebarSection(items: items().take(4).toList())],
              profileDestination: items().last,
              body: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tapSizes(tester).length, labels.length);
    for (final label in labels) {
      expect(tester.getSize(find.text(label)).width,
          closeTo(naturalWidth(tester, label), 0.5));
    }
    expect(tester.takeException(), isNull);
  });
}
