import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/ai_text_fold.dart';
import 'package:kids_learn/features/assistant/domain/assistant_event.dart';

AssistantEvent _sa(List<Map<String, dynamic>> actions) => AssistantEvent(
      eventType: AssistantEventType.suggestedActions,
      data: {'actions': actions},
    );

void main() {
  test('fold 解析 SUGGESTED_ACTIONS 帧为 suggestedActions 列表', () {
    final ev = _sa([
      {'label': '我要问个问题', 'kind': 'prompt', 'payload': 'q'},
      {'label': '看看孩子错题', 'kind': 'navigate', 'payload': 'teacher_task_list'},
    ]);
    final fold = const AiTextFold().apply(ev);
    expect(fold.suggestedActions.length, 2);
    expect(fold.suggestedActions[0].label, '我要问个问题');
    expect(fold.suggestedActions[0].kind, 'prompt');
    expect(fold.suggestedActions[1].kind, 'navigate');
    // 不影响正文/卡片/错误（仅入口，不污染对话内容）。
    expect(fold.isEmpty, isTrue);
    expect(fold.hasError, isFalse);
  });

  test('畸形/空 actions 帧被安全忽略（旧客户端不崩）', () {
    final badType = AssistantEvent(
      eventType: AssistantEventType.suggestedActions,
      data: {'actions': 'oops'},
    );
    expect(const AiTextFold().apply(badType).suggestedActions, isEmpty);

    final noData = AssistantEvent(eventType: AssistantEventType.suggestedActions);
    expect(const AiTextFold().apply(noData).suggestedActions, isEmpty);

    final empty = _sa(const []);
    expect(const AiTextFold().apply(empty).suggestedActions, isEmpty);
  });
}
