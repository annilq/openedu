// 守住一条已从崩溃里学到的约束：App 根是 ShadApp/CupertinoApp，**整棵 widget 树
// 没有 Material 祖先**。任何 Material 系控件（InkWell / Icons / Scaffold…）放进
// 消息流都会在构建期抛「No Material widget found」——不是某个按钮失灵，而是整片
// 消息流崩掉。
//
// 起因：引用条最初用 `InkWell` 做展开，真机上一有 rag_sources 就整页红屏。
// `flutter analyze` 完全照不出来，只有这种「在不装 Material 的树里真的构建一次」
// 的测试能拦住它。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_source.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_sources_bar.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

const _sources = <RagSource>[
  RagSource(
    materialId: 'm1',
    materialName: '三年级分数单元讲义',
    chunkId: 'c1',
    snippet: '分数的加减要先通分…',
  ),
  RagSource(
    materialId: 'm2',
    materialName: '错题本 2026 春',
    chunkId: 'c2',
    snippet: '常见错误：分子分母分别相加',
  ),
];

Future<void> _pumpBar(WidgetTester tester, List<RagSource> sources) async {
  await tester.pumpWidget(
    ProviderScope(
      // 刻意**不**套 Material：真实的 App 根就是 ShadApp + CupertinoApp。
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: AssistantSourcesBar(sources: sources),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('无 Material 祖先下能构建，且按资料去重', (tester) async {
    await _pumpBar(tester, _sources);

    // 构建没抛异常就是这条用例的主要断言（tester.pumpWidget 会重抛 FlutterError）。
    expect(tester.takeException(), isNull);
    expect(find.text('参考来源'), findsOneWidget);
    expect(find.text('三年级分数单元讲义'), findsOneWidget);
    expect(find.text('错题本 2026 春'), findsOneWidget);
  });

  testWidgets('点资料名展开片段摘要，再点收起', (tester) async {
    await _pumpBar(tester, _sources);

    expect(find.text('分数的加减要先通分…'), findsNothing);
    await tester.tap(find.text('三年级分数单元讲义'));
    await tester.pumpAndSettle();
    expect(find.text('分数的加减要先通分…'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('三年级分数单元讲义'));
    await tester.pumpAndSettle();
    expect(find.text('分数的加减要先通分…'), findsNothing);
  });

  testWidgets('同资料多片段合为一条', (tester) async {
    await _pumpBar(tester, const <RagSource>[
      RagSource(
          materialId: 'm1',
          materialName: '讲义',
          chunkId: 'c1',
          snippet: '第一段'),
      RagSource(
          materialId: 'm1',
          materialName: '讲义',
          chunkId: 'c2',
          snippet: '第二段'),
    ]);

    expect(find.text('讲义'), findsOneWidget);
    await tester.tap(find.text('讲义'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第一段'), findsOneWidget);
    expect(find.textContaining('第二段'), findsOneWidget);
  });

  testWidgets('来源为空时不占任何空间', (tester) async {
    await _pumpBar(tester, const <RagSource>[]);
    expect(find.text('参考来源'), findsNothing);
  });
}
