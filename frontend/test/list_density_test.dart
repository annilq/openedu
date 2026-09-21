// 守住列表密度的设计契约（ADR-0053 P1）。
//
// 背景：三个长列表（题库 / 任务 / 错题本）此前各有各的行距与页边距，家长错题卡
// 把完整题干 + 答案 + 整段解析一次全展开，且题干没有行数上限——一屏只看得到
// 三张半卡。这些都是「能跑但不好用」的问题，`flutter analyze` 照不出，只能守行为。
//
// 密度不靠压缩留白：卡片内边距维持 12 不动，靠的是内容截断、解析折叠、宽度够时
// 自动两列。本文件盯的正是这三条 + 行距 / 列距的统一。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/providers/selected_child_provider.dart';
import 'package:kids_learn/features/home/presentation/widgets/parent/parent_wrong_questions_view.dart';
import 'package:kids_learn/features/review/presentation/providers/review_notifier.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/presentation/paging.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_card_list.dart';

WrongQuestionModel _wrong({
  required String id,
  String stem = '小明有 12 颗糖，分给 3 个小朋友，每人分到几颗？请用算式表示。',
  String explanation = '把 12 平均分成 3 份，每份是 4，列式 12 ÷ 3 = 4。',
}) =>
    WrongQuestionModel(
      id: id,
      questionId: 'q-$id',
      subject: '数学',
      grade: 2,
      knowledgePoint: '表内除法',
      qtype: 'calc',
      stem: stem,
      answer: '4',
      explanation: explanation,
      wrongCount: 2,
      reviewStage: 1,
    );

/// 只为构造 notifier 存在：`select` 被覆盖成空实现，不会真的去取数。
class _NoopRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SeededSelectedChild extends SelectedChildNotifier {
  _SeededSelectedChild() : super(_NoopRef()) {
    state = const SelectedChild(id: 'c1', grade: 2);
  }

  @override
  void select(String id, int grade) {
    // 本测试不经它取数：避免触发 parentWrongQuestions 的真实加载。
  }
}

/// 直接给已加载态：本测试只关心卡片怎么画，不关心取数。
class _SeededWrongQuestions
    extends ParamPagingNotifier<WrongQuestionModel, String> {
  _SeededWrongQuestions(List<WrongQuestionModel> items)
      : super((id, {cursor}) async => throw UnimplementedError()) {
    state = PagingLoaded<WrongQuestionModel>(
      CursorPage<WrongQuestionModel>(
        items: items,
        total: items.length,
        pageSize: 20,
      ),
    );
  }
}

void main() {
  group('列数只由可用宽度决定', () {
    test('锚点宽度：1080 → 2 列；700 / 446 → 1 列', () {
      // 1080 = contentWide，减左右页边距后 1048，两列各 518。
      expect(AppLayout.listColumnsFor(1080 - 2 * AppLayout.listGutter), 2);
      expect(AppLayout.listColumnsFor(700 - 2 * AppLayout.listGutter), 1);
      // 侧栏展开后剩余可用宽度约 446 → 掉回 1 列，符合预期，不是 bug。
      expect(AppLayout.listColumnsFor(446), 1);
      // 上限 2 列：再宽也不排 3 列（3 列会把列宽压到 340，低于可读下限）。
      expect(AppLayout.listColumnsFor(3000), 2);
    });
  });

  group('两列布局的几何', () {
    Future<List<Rect>> pumpCardsAt(WidgetTester tester, double width) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            // Center 是必需的：MaterialApp 给 home 的是紧约束，直接放
            // SizedBox(width: 700) 会被拉回视口宽度，列数就静默测错档。
            home: Center(
              child: SizedBox(
                width: width,
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                          horizontal: AppLayout.listGutter),
                      sliver: AppCardSliver(
                        width: width,
                        itemCount: 4,
                        itemBuilder: (_, i) => SizedBox(
                          key: ValueKey('card$i'),
                          height: 120,
                          child: Text('card$i'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return [
        for (var i = 0; i < 4; i++)
          tester.getRect(find.byKey(ValueKey('card$i'))),
      ];
    }

    testWidgets('宽 1080：两列，列间距 = AppSpacing.md', (tester) async {
      final rects = await pumpCardsAt(tester, 1080);

      // 第 0 / 1 张同一行，第 2 张换到下一行。
      expect(rects[0].top, rects[1].top);
      expect(rects[2].top, greaterThan(rects[0].bottom));
      // 列间距比行间距大一档：列与列之间没有描边分隔，只能靠间距。
      expect(rects[1].left - rects[0].right,
          closeTo(AppLayout.listColumnGap, 0.5));
      expect(AppLayout.listColumnGap, greaterThan(AppLayout.listRowGap));
      // 两列各约 518：不能因为凑两列就把列宽压到可读下限以下。
      expect(rects[0].width, greaterThanOrEqualTo(AppLayout.contentNarrow));
    });

    testWidgets('宽 700：单列，卡片占满一行', (tester) async {
      final rects = await pumpCardsAt(tester, 700);

      expect(rects[1].top, greaterThan(rects[0].bottom));
      expect(rects[0].left, closeTo(rects[1].left, 0.5));
      expect(rects[0].width, closeTo(700 - 2 * AppLayout.listGutter, 0.5));
    });
  });

  group('家长错题卡的密度', () {
    Future<void> pumpCards(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            selectedChildProvider
                .overrideWith((ref) => _SeededSelectedChild()),
            parentWrongQuestionsProvider
                .overrideWith((ref) => _SeededWrongQuestions([_wrong(id: 'w1')])),
          ],
          child: ShadApp.custom(
            theme:
                AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
            appBuilder: (context) =>
                const MaterialApp(home: ParentWrongQuestionsView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('题干最多两行：长题干不撑掉半屏', (tester) async {
      await pumpCards(tester);

      // 断言的是「渲染出来的 Text 被限制在 2 行」，不是「源码里写了 maxLines」——
      // 后者改文案长度就失效，前者才是用户看到的东西。
      final text = tester.widget<Text>(find.textContaining('小明有 12 颗糖'));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);

      // 卡片整体高度受控：整卡展开前不应高过一屏的三分之一。
      final card = tester.getRect(find.textContaining('标准答案'));
      expect(card.height, lessThan(300));
    });

    testWidgets('解析默认折叠，点开后才出现', (tester) async {
      await pumpCards(tester);

      expect(find.textContaining('把 12 平均分成 3 份'), findsNothing,
          reason: '默认铺满解析会让列表被大段文字占满');

      await tester.tap(find.text('查看解析'));
      await tester.pumpAndSettle();

      expect(find.textContaining('把 12 平均分成 3 份'), findsOneWidget);

      await tester.tap(find.text('收起解析'));
      await tester.pumpAndSettle();
      expect(find.textContaining('把 12 平均分成 3 份'), findsNothing);
    });

    testWidgets('标准答案始终可见且只占一行', (tester) async {
      await pumpCards(tester);

      final answer = tester.widget<Text>(find.textContaining('标准答案').first);
      expect(answer.maxLines, 1);
      expect(answer.overflow, TextOverflow.ellipsis);
    });
  });
}
