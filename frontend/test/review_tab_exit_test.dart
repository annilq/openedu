import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/features/review/domain/repositories/review_repository.dart';
import 'package:kids_learn/features/review/presentation/screens/review_screen.dart';
import 'package:kids_learn/features/review/providers/review_provider.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_option_tile.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 复习页「返回」的行为守卫。
///
/// 背景（线上事故）：娃娃端复习页是导航空壳的**一个页签**（`IndexedStack` 常驻），
/// 不是 `Navigator.push` 出来的路由。它里面的两处 `Navigator.of(context).pop()`
/// （空态「返回」、完成卡「返回首页」）弹的是**根导航栈的最后一条路由**——也就是
/// 整个 App：点一下立刻白屏，之后任何一次重建都会撞上 `NavigatorState.build` 里的
/// `assert(_history.isNotEmpty)`（热重启 R 就是这个效果）。
///
/// 只断言「按钮存在」测不出这个 bug：pop 是真的执行了，只是弹错了栈。所以这里把
/// 页面放进一个**只挂一条路由的** MaterialApp（`home:`），点完返回后断言占位内容
/// 还在——被弹空的话它就没了（而且下一次 pump 会直接抛断言）。
Future<void> _pumpReview(
  WidgetTester tester, {
  required List<ReviewItemModel> items,
  required VoidCallback onExit,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reviewRepositoryProvider.overrideWithValue(_FakeReviewRepository(items)),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.child, AppDensity.compact),
        appBuilder: (_) => MaterialApp(
          home: Column(
            children: [
              const Text('壳占位'),
              Expanded(
                child: ReviewScreen(showBack: false, onExit: onExit),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ReviewItemModel _item() => ReviewItemModel(
      wrongQuestionId: 'w1',
      questionId: 'q1',
      subject: '数学',
      grade: 2,
      knowledgePoint: '加法',
      qtype: 'choice',
      stem: '1 + 1 = ?',
      options: const ['甲', '乙', '丙'],
      wrongCount: 1,
      reviewStage: 0,
      nextIntervalDays: 2,
    );

class _FakeReviewRepository implements ReviewRepository {
  _FakeReviewRepository(this.items);

  final List<ReviewItemModel> items;

  @override
  Future<List<ReviewItemModel>> dueReview() async => items;

  @override
  Future<AnswerResultModel> answer(
    String wrongQuestionId,
    String studentAnswer,
  ) async =>
      AnswerResultModel(correct: true, score: 1);

  @override
  Future<CursorPage<WrongQuestionModel>> childWrongQuestions({
    String? cursor,
    int pageSize = 20,
  }) async =>
      throw UnimplementedError();

  @override
  Future<WrongQuestionPage> parentWrongQuestions(
    String childId, {
    String? cursor,
    int pageSize = 20,
    String scope = 'active',
  }) async =>
      throw UnimplementedError();

  @override
  Future<WrongQuestionModel> rejoinWrongQuestion(
    String childId,
    String wrongQuestionId,
  ) async =>
      throw UnimplementedError();
}

void main() {
  testWidgets('空队列点「返回」走注入的出口，不弹根路由', (tester) async {
    var exits = 0;
    await _pumpReview(tester, items: const [], onExit: () => exits++);

    expect(find.text('今天没有要复习的题'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();

    expect(exits, 1, reason: '「返回」必须交回壳处理（切页签）');
    expect(find.text('壳占位'), findsOneWidget,
        reason: '根路由被弹空的话整棵树都没了——线上表现为白屏');
  });

  testWidgets('复习完成点「返回首页」走注入的出口，不弹根路由', (tester) async {
    var exits = 0;
    await _pumpReview(tester, items: [_item()], onExit: () => exits++);

    await tester.tap(find.widgetWithText(AppOptionTile, '乙'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交复习'));
    await tester.pumpAndSettle();
    // 结果弹窗：先关掉它才回到完成卡。
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.text('复习完成！'), findsOneWidget);
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();

    expect(exits, 1);
    expect(find.text('壳占位'), findsOneWidget);
  });

  testWidgets('没注入 onExit 时也不许把根路由弹空（maybePop 兜底）', (tester) async {
    // 组合根忘了注入是可能的（新调用点）；那也比白屏强：maybePop 在根栈只有
    // 一条路由时是 no-op。这条守住「兜底也是安全的」。
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewRepositoryProvider
              .overrideWithValue(_FakeReviewRepository(const [])),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.child, AppDensity.compact),
          appBuilder: (_) => const MaterialApp(
            home: Column(
              children: [
                Text('壳占位'),
                Expanded(child: ReviewScreen(showBack: false)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('壳占位'), findsOneWidget);
  });
}
