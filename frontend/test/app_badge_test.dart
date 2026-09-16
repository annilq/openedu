import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart' hide AppBadge;
import 'package:kids_learn/shared/widgets/app_badge.dart';

/// 守卫 AppBadge 的渲染：label 显示、outlined 默认底色、自定义底色/前景生效。
Widget _host(Widget child) => ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(home: child),
    );

void main() {
  testWidgets('渲染 label 文本', (tester) async {
    await tester.pumpWidget(_host(const AppBadge(label: '只读')));
    await tester.pumpAndSettle();
    expect(find.text('只读'), findsOneWidget);
  });

  testWidgets('outlined 变体：默认底色 surfaceSunken + 发丝描边', (tester) async {
    await tester.pumpWidget(_host(const AppBadge(label: '只读')));
    await tester.pumpAndSettle();
    final container = tester.widget<Container>(find.byType(Container).first);
    final deco = container.decoration! as BoxDecoration;
    expect(deco.color, AppTheme.light.surfaceSunken);
    expect(deco.border, isNotNull);
    expect((deco.border as Border).top.width, AppElevation.borderWidthSm);
  });

  testWidgets('自定义 background / foreground 覆盖默认', (tester) async {
    const bg = Color(0xFFDCE7FA);
    const fg = Color(0xFF1D4E9C);
    await tester.pumpWidget(_host(const AppBadge(
      label: '只读',
      background: bg,
      foreground: fg,
    )));
    await tester.pumpAndSettle();
    final container = tester.widget<Container>(find.byType(Container).first);
    final deco = container.decoration! as BoxDecoration;
    expect(deco.color, bg);
    final text = tester.widget<Text>(find.text('只读'));
    expect(text.style?.color, fg);
  });
}
