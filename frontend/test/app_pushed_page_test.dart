import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_content_frame.dart';
import 'package:kids_learn/shared/widgets/app_pushed_page.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 把整页放进**真实路由栈**里：退路（`maybePop` / Esc）在无可 pop 路由时什么都不做，
/// 只断言「控件存在」是测不出「真回得去」的（这条教训来自 ExportPreviewPage 上线事故）。
Future<void> _pumpPushed(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
      appBuilder: (_) => MaterialApp(
        navigatorKey: navigatorKey,
        home: const Text('来源页'),
      ),
    ),
  );
  navigatorKey.currentState!.push<void>(
    MaterialPageRoute<void>(builder: (_) => page),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AppPushedPage（push 整页的出路）', () {
    testWidgets('Esc 能离开这一页：桌面端不该只有鼠标一条路', (tester) async {
      await _pumpPushed(
        tester,
        const AppPushedPage(title: '打印预览', child: Text('正文')),
      );
      expect(find.text('来源页'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('来源页'), findsOneWidget);
    });

    testWidgets('返回键默认就在：退路是结构默认，不是每页自觉', (tester) async {
      // 关键：这里**没有**传 showBack。裸 AppTopBar 的默认 false 曾让
      // ExportPreviewPage 把人锁死一页——骨架必须把这个默认值反过来。
      await _pumpPushed(
        tester,
        const AppPushedPage(title: '打印预览', child: Text('正文')),
      );
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();

      expect(find.text('来源页'), findsOneWidget);
    });

    testWidgets('返回按钮有语义标签（不再是一个「无名按钮」）', (tester) async {
      await _pumpPushed(
        tester,
        const AppPushedPage(title: '打印预览', child: Text('正文')),
      );
      expect(find.bySemanticsLabel('返回'), findsOneWidget);
    });

    testWidgets('宽度仍守 contentWide 且内容贴顶（ADR-0045）', (tester) async {
      await _pumpPushed(
        tester,
        const AppPushedPage(title: '打印预览', child: Text('正文')),
      );
      final align = tester.widget<Align>(
        find
            .descendant(
              of: find.byType(AppPushedPage),
              matching: find.byType(Align),
            )
            .first,
      );
      expect(align.alignment, Alignment.topCenter);
      final box = tester.widget<ConstrainedBox>(
        find
            .descendant(
              of: find.byType(AppPushedPage),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(box.constraints.maxWidth, AppLayout.contentWide);
    });

    testWidgets('默认背景不被硬铺：不给 background 就不多一层 ColoredBox',
        (tester) async {
      await _pumpPushed(
        tester,
        const AppPushedPage(title: '打印预览', child: Text('正文')),
      );
      // 底部要通栏的页面带自己的底色/透明底，骨架不该擅自替它铺一层。
      expect(
        find.descendant(
          of: find.byType(AppPushedPage),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
    });
  });

  group('AppContentFrame（壳内也能复用同一个宽度出口）', () {
    testWidgets('对齐由调用方决定：壳内页面原本是 topLeft', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppContentFrame(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );
      final align = tester.widget<Align>(find.byType(Align));
      // 不是「统一成 topCenter」：迁移照抄原值，避免顺手改了别人的版式。
      expect(align.alignment, Alignment.topLeft);
    });

    testWidgets('可以钉更窄的上限（更紧者生效）', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppContentFrame(
            maxWidth: 480,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );
      final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(box.constraints.maxWidth, 480);
    });
  });
}
