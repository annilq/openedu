// 守住「写意图有出口」这条路：引导卡的动作解析 + 受控 target 映射 + 按钮真的可点。
//
// 背景（2026-09-17 真机报障）：家长说「帮我创建一个任务，包含四年级数学题」，
// 助手回「我这边只能查询…请到『任务/作业』相关页面操作」——回答没幻觉，
// 但**用户拿不到那个页面**：卡片协议当时只有 title/items/stats/text，
// 没有任何位置能放一个出口。后端补了 `guide` 卡与受控 target，
// 本文件守前端这一侧：解析不吞、未知 target 不猜、没有处理器时不画死按钮。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_card.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_cards.dart';
import 'package:kids_learn/shared/presentation/shell_navigation.dart';

/// 与 `assistant_card_test.dart` 同源的一份引导卡载荷（后端 `guide/agent.py` 的形状）。
Map<String, dynamic> _guideData() => {
      'type': 'guide',
      'result': {
        'title': '布置任务',
        'text': '到「布置任务」页选好题目，确认后发布给娃娃。',
        'actions': [
          {'label': '去布置任务', 'target': 'parent_create_task'},
          {'label': '先看看题库', 'target': 'parent_question_bank'},
        ],
      },
    };

void main() {
  group('AssistantCard.fromData · 引导卡动作', () {
    test('actions 解析出 label + target，且参与 hasContent', () {
      final card = AssistantCard.fromData(_guideData())!;
      expect(card.kind, AssistantCardKind.guide);
      expect(card.actions.length, 2);
      expect(card.actions.first.label, '去布置任务');
      expect(card.actions.first.target, 'parent_create_task');
    });

    test('缺 label 或 target 的一项整条丢弃——半张动作卡点了像界面坏了', () {
      final card = AssistantCard.fromData({
        'type': 'guide',
        'result': {
          'title': '布置任务',
          'actions': [
            {'label': '好的', 'target': ''},
            {'target': 'parent_create_task'},
            {'label': '去布置任务', 'target': 'parent_create_task'},
          ],
        },
      })!;
      expect(card.actions.length, 1);
      expect(card.actions.single.label, '去布置任务');
    });

    test('actions 非列表（类型歪）不炸，视为没有动作', () {
      final card = AssistantCard.fromData({
        'type': 'guide',
        'result': {'title': '布置任务', 'actions': 'oops'},
      })!;
      expect(card.actions, isEmpty);
      // 但说明文字还在——降级不丢内容。
      expect(card.hasContent, isTrue);
    });
  });

  group('ShellDestination.fromTarget · 受控值域', () {
    test('覆盖后端全部 target 常量', () {
      // 这三个字符串与后端 `app/ai/subagents/guide/agent.py` 的 TARGET_* 逐字对齐。
      for (final target in const [
        'parent_create_task',
        'parent_task_list',
        'parent_question_bank',
      ]) {
        expect(
          ShellDestination.fromTarget(target),
          isNotNull,
          reason: '$target 是后端会下发的 target，前端必须认得；否则按钮点了没反应',
        );
      }
    });

    test('未知 target 返回 null——宁可不动，也不猜一个近似落点', () {
      expect(ShellDestination.fromTarget('parent_delete_all_tasks'), isNull);
      expect(ShellDestination.fromTarget(''), isNull);
      expect(ShellDestination.fromTarget('https://evil.example.com'), isNull);
    });
  });

  group('AssistantCardTile · 引导卡渲染', () {
    Widget wrap(Widget child) => ShadApp.custom(
          appBuilder: (context) => MaterialApp(
            home: Scaffold(
              body: Center(child: SizedBox(width: 400, child: child)),
            ),
          ),
        );

    testWidgets('渲染出口按钮，点击把 target 交回宿主', (tester) async {
      AssistantCardAction? tapped;
      await tester.pumpWidget(wrap(AssistantCardTile(
        card: AssistantCard.fromData(_guideData())!,
        onAction: (action) => tapped = action,
      )));
      await tester.pumpAndSettle();

      expect(find.text('去布置任务'), findsOneWidget);
      expect(find.text('先看看题库'), findsOneWidget);

      await tester.tap(find.text('去布置任务'));
      await tester.pumpAndSettle();

      // 回调只交回动作本身：**怎么退、退到哪是宿主的事**
      // （家长端是 push 的整页、娃娃端是壳内页签），卡片不自己导航。
      expect(tapped?.target, 'parent_create_task');
    });

    testWidgets('宿主没给处理器时不画按钮（只读回放里点不动的按钮更糟）',
        (tester) async {
      await tester.pumpWidget(wrap(AssistantCardTile(
        card: AssistantCard.fromData(_guideData())!,
      )));
      await tester.pumpAndSettle();

      // 说明还在，出口不画。
      expect(find.text('到「布置任务」页选好题目，确认后发布给娃娃。'), findsOneWidget);
      expect(find.text('去布置任务'), findsNothing);
    });

    testWidgets('出口按钮键盘可达（Tab 到它 + Enter 激活）', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(AssistantCardTile(
        card: AssistantCard.fromData(_guideData())!,
        onAction: (_) => taps++,
      )));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(taps, 1,
          reason: '出口必须能键盘激活（ADR-0046）；裸 GestureDetector 时代这里是 0');
    });
  });
}
