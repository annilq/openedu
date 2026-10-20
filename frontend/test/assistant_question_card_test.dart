// 守住判断题卡的**揭示契约**（ADR-0090）：题卡连答案一起落对话历史（答案进历史是
// 「tutor 从历史读答案判定」的承重墙），因此「先判断再核对」的节奏只能由前端守——
// 未揭示时必须真的看不到答案，否则学生一进会话就被剧透。
//
// 这条契约此前零测试（spec 明记的必补缺口）：改题卡渲染的人可以无声破坏它，
// 而 `flutter analyze` 完全照不出（不是类型错误，是「文本还在不在」的行为问题）。
//
// 两条装置纪律：
// 1. **不套 Material**：App 根是 ShadApp + CupertinoApp，整棵树没有 Material 祖先，
//    任何 Material 控件都会在构建期抛错（先例 `assistant_sources_bar_test.dart`）。
// 2. **不截图**：测试环境无真实合成器，`RenderRepaintBoundary.toImage()` 永不完成，
//    实测把整条 `flutter test` 从 ~46s 堵到 17min。在场与否一律用文本断言。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_card.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_question_card.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_reasoning_disclosure.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_figure_gallery.dart';

/// 判断题卡（judge: true）：题干与对/错二选一照常显示，答案 / 解析 / 出题思路待揭示。
const _judgeCard = AssistantCard(
  kind: AssistantCardKind.question,
  rawPayload: <String, dynamic>{
    'subject': '数学',
    'grade': 3,
    'qtype': 'choice',
    'difficulty': 'easy',
    'stem': '把一个苹果平均分成两份，每份是它的 1/2。',
    // 判断题靠「choice + 选项仅为对/错」伪装（ADR-0004 D5），后端无独立题型键。
    'options': <String>['对', '错'],
    'answer': '对',
    'explanation': '平均分成两份，每份就是整体的二分之一。',
    'reasoning': '考「平均分」与分数单位的关系。',
    'judge': true,
  },
);

/// 普通题卡：非判断题不被阻碍，答案与解析照常即时可见。
const _plainCard = AssistantCard(
  kind: AssistantCardKind.question,
  rawPayload: <String, dynamic>{
    'subject': '数学',
    'grade': 3,
    'qtype': 'choice',
    'difficulty': 'medium',
    'stem': '1/2 + 1/4 = ?',
    'options': <String>['3/4', '2/6', '1/6'],
    'answer': '3/4',
    'explanation': '先通分成 2/4 + 1/4，再相加得 3/4。',
    'reasoning': '考异分母分数加法的通分步骤。',
    'judge': false,
  },
);

Future<void> _pumpCard(WidgetTester tester, AssistantCard card) async {
  await tester.pumpWidget(
    ShadApp.custom(
      // 刻意**不**套 Material：真实的 App 根就是 ShadApp + CupertinoApp。
      theme: AppTheme.shadFor(false, AppUserMode.student, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                // 与生产调用点同口径（`assistant_cards.dart`）：题卡左侧学科色条由
                // Row(stretch) 撑满卡片高度，消息流内高度无界，须 IntrinsicHeight
                // 给它一个有界高度——少了这层，构建期直接抛 infinite height。
                child: IntrinsicHeight(child: AssistantQuestionCard(card: card)),
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
  group('判断题卡未揭示', () {
    testWidgets('无 Material 祖先下能构建，题干与选项在场', (tester) async {
      await _pumpCard(tester, _judgeCard);

      // 构建没抛异常就是首要断言（pumpWidget 会重抛 FlutterError）。
      expect(tester.takeException(), isNull);
      expect(find.text('题目'), findsOneWidget);
      expect(find.text('把一个苹果平均分成两份，每份是它的 1/2。'), findsOneWidget);
      expect(find.text('对'), findsOneWidget);
      expect(find.text('错'), findsOneWidget);
    });

    testWidgets('答案 / 解析 / 出题思路三样均不在场', (tester) async {
      await _pumpCard(tester, _judgeCard);

      // 逐一断言，不能只断一样：三样是**各自**被 `showAnswer` 门控的三段渲染，
      // 少门控任何一段都会剧透。
      expect(find.textContaining('答案：'), findsNothing);
      expect(find.textContaining('解析：'), findsNothing);
      expect(find.text('出题思路'), findsNothing);
      expect(find.byType(AssistantReasoningDisclosure), findsNothing);
    });

    testWidgets('给出「先判断再核对」提示与「显示答案」动作', (tester) async {
      await _pumpCard(tester, _judgeCard);

      expect(find.textContaining('请判断「对」或「错」后回答'), findsOneWidget);
      expect(find.text('显示答案'), findsOneWidget);
    });
  });

  group('判断题卡揭示后', () {
    testWidgets('点「显示答案」渲染答案与解析', (tester) async {
      await _pumpCard(tester, _judgeCard);
      expect(find.textContaining('答案：'), findsNothing);

      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();

      expect(find.textContaining('答案：对'), findsOneWidget);
      expect(find.textContaining('解析：平均分成两份'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('揭示后收起提示与揭示入口，并放出出题思路', (tester) async {
      await _pumpCard(tester, _judgeCard);
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();

      // 已揭示，「显示答案」按钮与提示不该再占版面。
      expect(find.text('显示答案'), findsNothing);
      expect(find.textContaining('请判断「对」或「错」后回答'), findsNothing);
      // 出题思路随揭示一起放出（默认仍折叠），证明上一条「不在场」的断言不是空断言。
      expect(find.text('出题思路'), findsOneWidget);

      await tester.tap(find.text('出题思路'));
      await tester.pumpAndSettle();
      expect(find.text('考「平均分」与分数单位的关系。'), findsOneWidget);
    });
  });

  group('图形选项（ADR-0102）', () {
    // 后端把模型给的 figure_key 盖成内联几何后，选项是 {text, figure} 对象。
    const figureCard = AssistantCard(
      kind: AssistantCardKind.question,
      rawPayload: <String, dynamic>{
        'subject': '数学',
        'grade': 4,
        'qtype': 'choice',
        'difficulty': 'medium',
        'stem': '下面哪些图形是轴对称图形？',
        'options': <Map<String, dynamic>>[
          <String, dynamic>{
            'text': 'A. 正方形',
            'figure': <String, dynamic>{
              'key': 'square',
              'label': '正方形',
              'points': <List<double>>[
                <double>[0.28, 0.28],
                <double>[0.72, 0.28],
                <double>[0.72, 0.72],
                <double>[0.28, 0.72],
              ],
              'edges': <List<int>>[
                <int>[0, 1],
                <int>[1, 2],
                <int>[2, 3],
                <int>[3, 0],
              ],
            },
          },
          <String, dynamic>{
            'text': 'B. 平行四边形',
            'figure': <String, dynamic>{
              'key': 'para',
              'label': '平行四边形',
              'points': <List<double>>[
                <double>[0.30, 0.40],
                <double>[0.70, 0.40],
                <double>[0.82, 0.70],
                <double>[0.42, 0.70],
              ],
              'edges': <List<int>>[
                <int>[0, 1],
                <int>[1, 2],
                <int>[2, 3],
                <int>[3, 0],
              ],
            },
          },
        ],
        'answer': 'A. 正方形',
        'explanation': '正方形有四条对称轴。',
      },
    );

    testWidgets('选项文字正常渲染，不把 {text, figure} 打成 map 字符串', (tester) async {
      await _pumpCard(tester, figureCard);

      expect(tester.takeException(), isNull);
      // 回归的是：原来逐条 cardStr 会把 dict 变成 "{text: A. 正方形, figure: …}"
      expect(find.textContaining('{text'), findsNothing);
      expect(find.textContaining('figure'), findsNothing);
      // 字母前缀由渲染层重画，正文里模型自带的 "A. " 必须剥掉
      expect(find.text('正方形'), findsOneWidget);
      expect(find.text('平行四边形'), findsOneWidget);
    });

    testWidgets('每个带图形的选项渲染一张缩略图', (tester) async {
      await _pumpCard(tester, figureCard);

      // 两个选项各有一张缩略图。断言按 painter 类型，不用裸 CustomPaint——
      // shadcn/Cupertino 内部也画 CustomPaint，按类型数会数到别人的。
      final thumbs = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FigureThumbPainter,
        description: '图形缩略图',
      );
      expect(thumbs, findsNWidgets(2));
    });

    testWidgets('无图形选项时不渲染缩略图（纯文字题零变化）', (tester) async {
      await _pumpCard(tester, _plainCard);

      final thumbs = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FigureThumbPainter,
        description: '图形缩略图',
      );
      expect(thumbs, findsNothing);
      expect(find.text('3/4'), findsOneWidget);
    });
  });

  group('非判断题卡', () {
    testWidgets('答案与解析默认在场，不被揭示机制阻碍', (tester) async {
      await _pumpCard(tester, _plainCard);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('答案：3/4'), findsOneWidget);
      expect(find.textContaining('解析：先通分'), findsOneWidget);
    });

    testWidgets('无「显示答案」动作与待判定提示', (tester) async {
      await _pumpCard(tester, _plainCard);

      expect(find.text('显示答案'), findsNothing);
      expect(find.textContaining('请判断「对」或「错」后回答'), findsNothing);
    });
  });
}
