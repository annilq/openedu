import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/ai_text_fold.dart';
import 'package:kids_learn/features/assistant/domain/assistant_event.dart';

/// 把一串事件喂给 [AiTextFold]，返回最终折叠结果（纯函数，无需 SSE / mock）。
AiTextFold foldAll(List<AssistantEvent> events) =>
    events.fold(const AiTextFold(), (f, ev) => f.apply(ev));

void main() {
  group('AiTextFold · 正文累加', () {
    test('多帧 ASSISTANT_MESSAGE 按顺序拼成完整文本', () {
      final f = foldAll([
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '先算个位',
        ),
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '，再算十位',
        ),
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '，结果是 68。',
        ),
      ]);

      expect(f.text, '先算个位，再算十位，结果是 68。');
      expect(f.isEmpty, isFalse);
    });

    test('text 为 null 的帧不污染已累积文本', () {
      final f = foldAll([
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: 'abc',
        ),
        AssistantEvent(eventType: AssistantEventType.assistantMessage),
      ]);

      expect(f.text, 'abc');
    });

    test('apply 不改接收者（纯函数）', () {
      const before = AiTextFold();
      final after = before.apply(
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: 'hi',
        ),
      );

      expect(before.text, '');
      expect(after.text, 'hi');
    });
  });

  group('AiTextFold · 不渲染的帧', () {
    test('THINKING / TOOL_* / STEP / RUN_STARTED / DONE 原样透传', () {
      const before = AiTextFold(text: '已有正文');
      for (final type in [
        AssistantEventType.runStarted,
        AssistantEventType.thinking,
        AssistantEventType.toolCall,
        AssistantEventType.toolResult,
        AssistantEventType.step,
        AssistantEventType.done,
        AssistantEventType.userMessage,
      ]) {
        final after = before.apply(
          AssistantEvent(eventType: type, text: '不应拼接'),
        );
        expect(after.text, '已有正文', reason: '$type 不应改变正文');
        expect(after.cards, isEmpty, reason: '$type 不应产生卡片');
      }
    });
  });

  group('AiTextFold · DATA 卡片', () {
    test('result 是 Map 时挂载卡片，且按到达顺序累积', () {
      final f = foldAll([
        AssistantEvent(
          eventType: AssistantEventType.data,
          data: {
            'type': 'question',
            'result': {'stem': '1+1=?'},
          },
        ),
        AssistantEvent(
          eventType: AssistantEventType.data,
          data: {
            'type': 'question',
            'result': {'stem': '2+2=?'},
          },
        ),
      ]);

      expect(f.cards.length, 2);
      expect(f.cards.first['stem'], '1+1=?');
      expect(f.cards.last['stem'], '2+2=?');
    });

    test('result 非 Map / data 为空时不挂卡片', () {
      final f = foldAll([
        AssistantEvent(
          eventType: AssistantEventType.data,
          data: {'type': 'question', 'result': 'not-a-map'},
        ),
        AssistantEvent(eventType: AssistantEventType.data),
      ]);

      expect(f.cards, isEmpty);
      expect(f.isEmpty, isTrue);
    });
  });

  group('AiTextFold · 错误与安全兜底', () {
    test('ERROR 帧记录文案，并给出默认兜底文案', () {
      final withMessage = foldAll([
        AssistantEvent(eventType: AssistantEventType.error, message: '配额用尽'),
      ]);
      expect(withMessage.hasError, isTrue);
      expect(withMessage.errorText, '配额用尽');

      final withoutMessage = foldAll([
        AssistantEvent(eventType: AssistantEventType.error),
      ]);
      expect(withoutMessage.errorText, '出错了，请稍后重试');
    });

    test('INPUT_UNSAFE 标 blocked，其它错误码不标', () {
      final unsafe = foldAll([
        AssistantEvent(
          eventType: AssistantEventType.error,
          code: AssistantErrorCode.inputUnsafe,
          message: '输入含不安全内容',
        ),
      ]);
      expect(unsafe.blocked, isTrue);

      final other = foldAll([
        AssistantEvent(
          eventType: AssistantEventType.error,
          code: 'SOMETHING_ELSE',
          message: '出错了',
        ),
      ]);
      expect(other.blocked, isFalse);
      expect(other.hasError, isTrue);
    });

    test('正文先到、错误后到：两者都保留（错误另起一条气泡）', () {
      final f = foldAll([
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '部分回答',
        ),
        AssistantEvent(
          eventType: AssistantEventType.error,
          code: AssistantErrorCode.inputUnsafe,
          message: '后续被拦截',
        ),
      ]);

      expect(f.text, '部分回答');
      expect(f.errorText, '后续被拦截');
      expect(f.blocked, isTrue);
    });
  });
}
