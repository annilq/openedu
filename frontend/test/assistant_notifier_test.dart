import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/data/assistant_api_client.dart';
import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/assistant/presentation/provider/assistant_notifier.dart';

/// 假 AssistantApiClient：按预设逐帧产出 AG-UI 事件。
class _FakeAssistant extends Fake implements AssistantApiClient {
  _FakeAssistant({this.events = const [], this.error});

  final List<AssistantEvent> events;
  final Object? error;

  @override
  Stream<AssistantEvent> streamChat(AssistantChatReq req) =>
      error == null ? Stream.fromIterable(events) : Stream.error(error!);
}

List<AssistantMessage> _aiBubbles(AssistantState state) =>
    (state as AssistantActive).messages.where((m) => m.role == 'ai').toList();

void main() {
  group('AssistantNotifier · 事件解释（委托 AiTextFold）', () {
    test('多帧 ASSISTANT_MESSAGE 累加成一条 AI 气泡', () async {
      final notifier = AssistantNotifier(_FakeAssistant(events: [
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '先算个位',
        ),
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '，结果是 68。',
        ),
      ]));

      await notifier.send('23+45 怎么算');

      final state = notifier.state as AssistantActive;
      expect(state.streaming, isFalse);
      final ai = _aiBubbles(state);
      expect(ai.length, 1);
      expect(ai.single.text, '先算个位，结果是 68。');
      expect(ai.single.thinking, isFalse);
    });

    test('流期间显示思考中占位，结束后必须消失（空事件流不留空气泡）', () async {
      final notifier = AssistantNotifier(_FakeAssistant());

      final future = notifier.send('你好');
      expect(notifier.state, isA<AssistantActive>());
      await future;

      final state = notifier.state as AssistantActive;
      expect(state.streaming, isFalse);
      // 只剩娃娃那条 user 气泡，AI 占位已清掉。
      expect(state.messages.where((m) => m.thinking), isEmpty);
      expect(state.messages.map((m) => m.role).toList(), ['user']);
    });

    test('流异常时也不残留占位气泡，并追加错误提示', () async {
      final notifier = AssistantNotifier(
        _FakeAssistant(error: Exception('连接中断')),
      );

      await notifier.send('你好');

      final state = notifier.state as AssistantActive;
      expect(state.error, isTrue);
      expect(state.messages.where((m) => m.thinking), isEmpty);
      expect(state.messages.last.text, contains('连接中断'));
    });

    test('DATA 帧挂载卡片到同一条 AI 气泡', () async {
      final notifier = AssistantNotifier(_FakeAssistant(events: [
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '这几道题练一下：',
        ),
        AssistantEvent(
          eventType: AssistantEventType.data,
          data: {
            'type': 'question',
            'result': {'stem': '1+1=?'},
          },
        ),
      ]));

      await notifier.send('出两道加法');

      final ai = _aiBubbles(notifier.state);
      expect(ai.length, 1);
      expect(ai.single.text, '这几道题练一下：');
      expect(ai.single.cards?.single['stem'], '1+1=?');
    });

    test('INPUT_UNSAFE：气泡标 blocked 且正文与错误各一条', () async {
      final notifier = AssistantNotifier(_FakeAssistant(events: [
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '部分回答',
        ),
        AssistantEvent(
          eventType: AssistantEventType.error,
          code: AssistantErrorCode.inputUnsafe,
          message: '输入含不安全内容',
        ),
      ]));

      await notifier.send('不合适的问题');

      final ai = _aiBubbles(notifier.state);
      expect(ai.length, 2);
      expect(ai.first.text, '部分回答');
      expect(ai.last.text, '输入含不安全内容');
      expect(ai.last.blocked, isTrue);
    });
  });
}
