// 守住 ADR-0045 的键盘可达性契约。
//
// 背景：本仓的可点区域过去一律是**裸 GestureDetector**，而裸 GestureDetector 不在
// 焦点树里——Tab 跳不过去、Enter/Space 也点不动。`flutter analyze` 照不出这类问题
// （它不是类型错误），所以只能用行为测试守。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';

void main() {
  /// ShadApp 提供 ShadTheme（AppCard / AppTheme.colorsOf 需要），
  /// MaterialApp 提供 Tab → NextFocusIntent 等默认快捷键与 Material 祖先。
  Widget wrap(Widget child) => ShadApp.custom(
        appBuilder: (context) => MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 400, child: child)),
          ),
        ),
      );

  Future<void> tabTo(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }

  testWidgets('可点卡片键盘可达：Tab 到它、Enter 激活', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(AppCard.listRow(
      onTap: () => taps++,
      child: const Text('任务一行'),
    )));
    await tester.pumpAndSettle();

    await tabTo(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(taps, 1,
        reason: '可点卡片必须能用键盘激活；裸 GestureDetector 时代这里是 0');
  });

  testWidgets('可点卡片键盘可达：Space 同样激活', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(AppCard.listRow(
      onTap: () => taps++,
      child: const Text('任务一行'),
    )));
    await tester.pumpAndSettle();

    await tabTo(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('不可点卡片不进焦点树（不应被 Tab 到）', (tester) async {
    var otherTaps = 0;
    await tester.pumpWidget(wrap(Column(
      children: [
        // 纯展示卡：无 onTap → 不该抢焦点。
        const AppCard(child: Text('只读卡')),
        AppCard.listRow(
          onTap: () => otherTaps++,
          child: const Text('可点卡'),
        ),
      ],
    )));
    await tester.pumpAndSettle();

    // 第一次 Tab 应直接落到「可点卡」，而不是被只读卡吃掉。
    await tabTo(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(otherTaps, 1, reason: '无可点行为的卡片不该进入 Tab 序列');
  });

  testWidgets('键盘激活也会走一次按压反馈（onPressedChanged true→false）',
      (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(wrap(AppFocusableAction(
      onTap: () {},
      onPressedChanged: seen.add,
      child: const Text('任务一行'),
    )));
    await tester.pumpAndSettle();

    await tabTo(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(seen, [true, false],
        reason: '键盘没有 onTapDown/Up，需由 AppFocusableAction 补齐一次按压反馈');
  });
}
