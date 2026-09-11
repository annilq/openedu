import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/assistant/domain/question_gen_fold.dart';

/// 把一串事件喂给 [QuestionGenFold]，返回最终折叠结果（纯函数，无需 SSE / mock）。
QuestionGenFold foldAll(List<AssistantEvent> events) =>
    events.fold(const QuestionGenFold(), (f, ev) => f.apply(ev));

AssistantEvent questionCard(String stem) => AssistantEvent(
      eventType: AssistantEventType.data,
      data: {
        'type': 'question',
        'result': {'stem': stem, 'subject': '数学', 'grade': 2, 'qtype': 'calc'},
      },
    );

void main() {
  group('QuestionGenFold · 推理区', () {
    test('多帧 THINKING 单调累加，不丢帧（推理闪现回归）', () {
      final f = foldAll([
        AssistantEvent(eventType: AssistantEventType.step, label: '第 1 题'),
        AssistantEvent(eventType: AssistantEventType.thinking, text: '先想进位'),
        AssistantEvent(eventType: AssistantEventType.thinking, text: '，再定难度'),
        AssistantEvent(eventType: AssistantEventType.thinking, text: '，最后配图'),
      ]);

      expect(f.liveReasoning, '先想进位，再定难度，最后配图');
      expect(f.liveIndex, 0);
      expect(f.liveLabel, '第 1 题');
    });

    test('路由 THINKING 帧（extra.business / extra.routing）不进推理区', () {
      final f = foldAll([
        AssistantEvent(eventType: AssistantEventType.thinking, text: '真推理'),
        AssistantEvent(
          eventType: AssistantEventType.thinking,
          text: '正在选择助手…',
          extra: {'business': 'question'},
        ),
        AssistantEvent(
          eventType: AssistantEventType.thinking,
          text: '正在路由…',
          extra: {'routing': true},
        ),
      ]);

      expect(f.liveReasoning, '真推理');
    });

    test('STEP 帧：序号推进到下一题并清空上一题推理', () {
      late QuestionGenFold f;
      f = const QuestionGenFold()
          .apply(AssistantEvent(eventType: AssistantEventType.step))
          .apply(
            AssistantEvent(
              eventType: AssistantEventType.thinking,
              text: '第 1 题思路',
            ),
          )
          .apply(questionCard('1+1=?'))
          .apply(AssistantEvent(eventType: AssistantEventType.step))
          .apply(
            AssistantEvent(
              eventType: AssistantEventType.thinking,
              text: '第 2 题思路',
            ),
          );

      expect(f.questions.length, 1);
      expect(f.liveIndex, 1, reason: '题卡已落位 1 张，当前应是第 2 题');
      expect(f.liveReasoning, '第 2 题思路');
    });

    test('题卡到达：内联区折叠（index 归 -1、标签与推理清空）', () {
      final f = foldAll([
        AssistantEvent(eventType: AssistantEventType.step, label: '出题中'),
        AssistantEvent(eventType: AssistantEventType.thinking, text: '思路'),
        questionCard('1+1=?'),
      ]);

      expect(f.questions.length, 1);
      expect(f.questions.first.stem, '1+1=?');
      expect(f.liveIndex, -1);
      expect(f.liveLabel, '');
      expect(f.liveReasoning, '');
    });

    test('TOOL_CALL 置进度标签，TOOL_RESULT 折叠内联区', () {
      final f = foldAll([
        AssistantEvent(eventType: AssistantEventType.toolCall, label: '检索教材'),
        AssistantEvent(eventType: AssistantEventType.toolResult),
      ]);

      expect(f.liveLabel, '');
      expect(f.liveIndex, -1);
    });

    test('TOOL_CALL 无 label 时回落「生成中」', () {
      final f = const QuestionGenFold().apply(
        AssistantEvent(eventType: AssistantEventType.toolCall),
      );
      expect(f.liveLabel, '生成中');
    });
  });

  group('QuestionGenFold · 题卡', () {
    test('只收 type=question 且 result 是 Map 的 DATA 帧', () {
      final f = foldAll([
        questionCard('1+1=?'),
        AssistantEvent(
          eventType: AssistantEventType.data,
          data: {'type': 'query', 'result': {'foo': 'bar'}},
        ),
        AssistantEvent(
          eventType: AssistantEventType.data,
          data: {'type': 'question', 'result': 'not-a-map'},
        ),
      ]);

      expect(f.questions.length, 1);
      expect(f.questions.first.stem, '1+1=?');
    });

    test('多张题卡按到达顺序保留', () {
      final f = foldAll([questionCard('A'), questionCard('B')]);
      expect(f.questions.map((q) => q.stem).toList(), ['A', 'B']);
    });
  });

  group('QuestionGenFold · 收尾', () {
    test('ERROR 帧记录文案，无 message 时回落「生成失败」', () {
      final withMessage = foldAll([
        AssistantEvent(eventType: AssistantEventType.error, message: '模型超时'),
      ]);
      expect(withMessage.hasError, isTrue);
      expect(withMessage.errorText, '模型超时');

      final withoutMessage = foldAll([
        AssistantEvent(eventType: AssistantEventType.error),
      ]);
      expect(withoutMessage.errorText, '生成失败');
    });

    test('0 题收尾：优先回显后端 ASSISTANT_MESSAGE，否则用兜底文案', () {
      final withHint = foldAll([
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '本次未能生成题目，请调整科目或年级后重试。',
        ),
      ]);
      expect(withHint.questions, isEmpty);
      expect(withHint.emptyMessage, '本次未能生成题目，请调整科目或年级后重试。');

      expect(const QuestionGenFold().emptyMessage,
          '本次未能生成题目，请调整科目或年级后重试。');
    });

    test('apply 不改接收者（纯函数）', () {
      const before = QuestionGenFold();
      final after = before.apply(questionCard('1+1=?'));

      expect(before.questions, isEmpty);
      expect(after.questions.length, 1);
    });
  });
}
