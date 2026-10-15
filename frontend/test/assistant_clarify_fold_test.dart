import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/ai_text_fold.dart';
import 'package:kids_learn/features/assistant/domain/assistant_event.dart';

/// 澄清帧的解析（ADR-0095）：后端不新增事件类型，只在普通 ASSISTANT_MESSAGE 的
/// `extra.clarify` 里多带一份缺槽清单；前端在此把它收成 [AiTextFold.clarifySlots]。
void main() {
  test('extra.clarify.missing_slots 收进 clarifySlots', () {
    const ev = AssistantEvent(
      eventType: AssistantEventType.assistantMessage,
      text: '请问要出哪个科目？ 几年级？（1-9）',
      extra: {
        'clarify': {
          'missing_slots': [
            {
              'name': 'subject',
              'prompt': '请问要出哪个科目？',
              'type': 'enum',
              'enum': ['数学', '语文', '英语'],
              'min': null,
              'max': null,
            },
            {
              'name': 'grade',
              'prompt': '几年级？（1-9）',
              'type': 'int',
              'enum': null,
              'min': 1,
              'max': 9,
            },
          ],
        },
      },
    );

    final fold = const AiTextFold().apply(ev);

    // 澄清帧**同时**是普通正文（各缺槽 prompt 拼成的句子），不是二选一
    expect(fold.text, contains('请问要出哪个科目？'));
    expect(fold.clarifySlots.length, 2);
    expect(fold.clarifySlots[0].name, 'subject');
    expect(fold.clarifySlots[0].values, ['数学', '语文', '英语']);
    expect(fold.clarifySlots[1].name, 'grade');
    expect(fold.clarifySlots[1].min, 1);
    expect(fold.clarifySlots[1].max, 9);
  });

  test('普通消息帧无 clarify → 空列表（按普通正文渲染）', () {
    const ev = AssistantEvent(
      eventType: AssistantEventType.assistantMessage,
      text: '已确认规格：科目=数学',
    );
    final fold = const AiTextFold().apply(ev);
    expect(fold.text, '已确认规格：科目=数学');
    expect(fold.clarifySlots, isEmpty);
  });

  test('畸形 clarify（非 Map / 非 List）降级为空，不抛', () {
    for (final badExtra in <Map<String, dynamic>>[
      {'clarify': 'oops'},
      {'clarify': {'missing_slots': 'oops'}},
      {'clarify': {}},
    ]) {
      final ev = AssistantEvent(
        eventType: AssistantEventType.assistantMessage,
        text: '你好',
        extra: badExtra,
      );
      expect(const AiTextFold().apply(ev).clarifySlots, isEmpty);
    }
  });
}
