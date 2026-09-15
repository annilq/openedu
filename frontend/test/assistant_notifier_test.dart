import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/assistant_requests.dart';
import 'package:kids_learn/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:kids_learn/features/assistant/domain/assistant_card.dart';
import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/assistant/presentation/provider/assistant_notifier.dart';

/// 假 AssistantRepository：按预设逐帧产出 AG-UI 事件。
class _FakeAssistant extends Fake implements AssistantRepository {
  _FakeAssistant({this.events = const [], this.error});

  final List<AssistantEvent> events;
  final Object? error;

  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) =>
      error == null ? Stream.fromIterable(events) : Stream.error(error!);
}

List<AssistantMessage> _aiBubbles(AssistantState state) =>
    (state as AssistantActive).messages.where((m) => m.role == 'ai').toList();

/// 记录每轮请求体的假客户端：用于断言会话 id 与兜底历史的传递（多轮续接）。
///
/// `_scripts` 按调用次序逐条消费，用尽后重复最后一条（便于「同一响应多轮复用」）。
class _RecordingAssistant extends Fake implements AssistantRepository {
  _RecordingAssistant(this._scripts);

  final List<List<AssistantEvent>> _scripts;
  final List<AssistantChatReq> requests = [];
  int _cursor = 0;

  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) {
    requests.add(req);
    final idx = _cursor < _scripts.length ? _cursor : _scripts.length - 1;
    _cursor++;
    return Stream.fromIterable(_scripts[idx]);
  }
}

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
      // 卡片与文本同挂一条气泡；种类来自信封 type，载荷原样可读（ADR-0042）。
      expect(ai.single.cards?.single.kind, AssistantCardKind.question);
      expect(ai.single.cards?.single.rawPayload['stem'], '1+1=?');
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

  group('AssistantNotifier · 多轮会话续接', () {
    test('首轮不带 session_id，DONE 帧回写的 id 在下一轮原样带回', () async {
      final client = _RecordingAssistant([
        [AssistantEvent(eventType: AssistantEventType.done, sessionId: 'conv-1')],
      ]);
      final notifier = AssistantNotifier(client);

      await notifier.send('第一问');
      expect(client.requests.single.sessionId, isNull, reason: '首轮无会话，交后端新建');

      await notifier.send('第二问');
      expect(client.requests.last.sessionId, 'conv-1', reason: '续接首轮回写的会话');
    });

    test('后端回写新 id 时前端覆盖旧的（归属校验失败自愈）', () async {
      final client = _RecordingAssistant([
        [AssistantEvent(eventType: AssistantEventType.done, sessionId: 'conv-1')],
        [AssistantEvent(eventType: AssistantEventType.done, sessionId: 'conv-2')],
        [AssistantEvent(eventType: AssistantEventType.done, sessionId: 'conv-2')],
      ]);
      final notifier = AssistantNotifier(client);

      await notifier.send('a');
      await notifier.send('b');
      await notifier.send('c');

      expect(client.requests[1].sessionId, 'conv-1');
      expect(client.requests[2].sessionId, 'conv-2', reason: '被后端换掉的 id 不再使用');
    });

    test('reset 清空气泡与会话 id，下一轮重新建会话', () async {
      final client = _RecordingAssistant([
        [AssistantEvent(eventType: AssistantEventType.done, sessionId: 'conv-1')],
      ]);
      final notifier = AssistantNotifier(client);

      await notifier.send('a');
      notifier.reset();
      expect(notifier.state, isA<AssistantInitial>());

      await notifier.send('b');
      expect(client.requests.last.sessionId, isNull, reason: '重置后从零开始');
    });

    test('兜底 history 对齐后端契约（content 键 + assistant 角色）并截最近 20 条', () async {
      final client = _RecordingAssistant([
        [AssistantEvent(eventType: AssistantEventType.assistantMessage, text: '答案 A')],
      ]);
      final notifier = AssistantNotifier(client);

      await notifier.send('问题一');
      expect(client.requests.first.history, isEmpty, reason: '首轮无历史可带');

      await notifier.send('问题二');
      expect(client.requests.last.history, [
        {'role': 'user', 'content': '问题一'},
        {'role': 'assistant', 'content': '答案 A'},
      ], reason: '键名是 content 而非 text，role 是 assistant 而非 ai');

      // 再灌 10 轮（每轮 +2 条气泡），兜底历史须被截到后端同款的 20 条。
      for (var i = 0; i < 10; i++) {
        await notifier.send('追问 $i');
      }
      expect(client.requests.last.history, hasLength(20));
    });
  });
}
