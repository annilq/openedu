import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_select_strip.dart';

/// 守卫 AppSelectStrip 的渲染与状态文案：非勾选态入口、勾选态计数、hint 引导语。
Widget _host(Widget child) => ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(home: child),
    );

void main() {
  testWidgets('非勾选态：右侧显示「多选」入口，无勾选计数', (tester) async {
    await tester.pumpWidget(_host(const AppSelectStrip(
      selecting: false,
      selectedCount: 0,
      totalCount: 5,
      onEnterSelecting: _noop,
      onToggleSelectAll: _noop,
    )));
    await tester.pumpAndSettle();

    expect(find.text('多选'), findsOneWidget);
    expect(find.text('已选 0 项'), findsNothing);
    expect(find.text('全选'), findsNothing);
  });

  testWidgets('勾选态：左侧计数「已选 N 项」、右侧「全选」按钮', (tester) async {
    await tester.pumpWidget(_host(const AppSelectStrip(
      selecting: true,
      selectedCount: 2,
      totalCount: 5,
      onEnterSelecting: _noop,
      onToggleSelectAll: _noop,
    )));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 项'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('多选'), findsNothing);
  });

  testWidgets('勾选态且 0 选：传 hintText 时左侧显示引导语而非「已选 0 项」',
      (tester) async {
    await tester.pumpWidget(_host(const AppSelectStrip(
      selecting: true,
      selectedCount: 0,
      totalCount: 5,
      onEnterSelecting: _noop,
      onToggleSelectAll: _noop,
      hintText: '勾选要删除的会话',
    )));
    await tester.pumpAndSettle();

    expect(find.text('勾选要删除的会话'), findsOneWidget);
    expect(find.text('已选 0 项'), findsNothing);
    expect(find.text('全选'), findsOneWidget);
  });

  testWidgets('勾选态 0 选且未传 hintText：回退显示「已选 0 项」', (tester) async {
    await tester.pumpWidget(_host(const AppSelectStrip(
      selecting: true,
      selectedCount: 0,
      totalCount: 5,
      onEnterSelecting: _noop,
      onToggleSelectAll: _noop,
    )));
    await tester.pumpAndSettle();

    expect(find.text('已选 0 项'), findsOneWidget);
  });
}

void _noop() {}
