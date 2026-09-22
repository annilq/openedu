import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// [AppDialog] 的「不弹根路由」守卫。
///
/// 背景：同 `review_tab_exit_test` 的线上事故——对话框按钮若用**调用方的**
/// `context` 去 `Navigator.pop`，而该 `context` 的就近 Navigator 恰好是根栈，
/// 弹错栈就会把整个 App 弹空（白屏 + 下次重建撞 `_history.isNotEmpty` 断言）。
///
/// 这里把对话框放进**只挂一条路由**的 MaterialApp（`home:`），点完按钮后：
/// ① 对话框必须真的消失；② 占位内容必须还在——被弹空的话它就没了。
Future<void> _pumpShell(WidgetTester tester, Widget dialog) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
        appBuilder: (_) => MaterialApp(
          home: Column(
            children: [
              const Text('壳占位'),
              Expanded(child: dialog),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('alert 点「继续」关掉自己，不弹根路由', (tester) async {
    await _pumpShell(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => AppDialog.alert(
            context,
            title: const Text('提示'),
            content: const Text('一条提示'),
          ),
          child: const Text('打开'),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('一条提示'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.text('一条提示'), findsNothing, reason: '对话框必须已关闭');
    expect(find.text('壳占位'), findsOneWidget,
        reason: '根路由被弹空的话整棵树都没了——线上表现为白屏');
  });

  testWidgets('confirm 取消/确认都只关自己，不弹根路由', (tester) async {
    for (final label in ['取消', '确定']) {
      await _pumpShell(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AppDialog.confirm(
              context,
              title: const Text('确认？'),
              content: const Text('确认内容'),
            ),
            child: const Text('打开'),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('确认内容'), findsOneWidget);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(find.text('确认内容'), findsNothing, reason: '对话框必须已关闭');
      expect(find.text('壳占位'), findsOneWidget,
          reason: '根路由被弹空的话整棵树都没了——线上表现为白屏');
    }
  });
}
