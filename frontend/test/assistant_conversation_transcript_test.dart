import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/assistant_card.dart';
import 'package:kids_learn/features/assistant/presentation/conversation_transcript.dart';
import 'package:kids_learn/features/assistant/presentation/provider/assistant_notifier.dart';

/// [buildConversationMarkdown] 是「导出对话」的纯逻辑：把内存里的消息压成可读文本，
/// 不走网络、不依赖原生，断言喂消息即可、稳定可测。
void main() {
  group('buildConversationMarkdown', () {
    test('用户与 AI 各标角色，正文原样保留', () {
      final md = buildConversationMarkdown([
        AssistantMessage(role: 'user', text: '什么是分数？'),
        AssistantMessage(
            role: 'ai', text: '把整体平均分成若干份，取其中一份就是分数。'),
      ]);

      expect(md, contains('**我：**'));
      expect(md, contains('什么是分数？'));
      expect(md, contains('**AI 老师：**'));
      expect(md, contains('把整体平均分成若干份'));
    });

    test('占位「思考中」气泡无正文，导出时跳过', () {
      final md = buildConversationMarkdown([
        AssistantMessage(role: 'user', text: '再来一道'),
        AssistantMessage(role: 'ai', thinking: true),
      ]);

      expect(md, isNot(contains('思考中')));
      // 仍有用户提问，故不是空态
      expect(md, contains('再来一道'));
    });

    test('被安全限制的回复标提示而非丢内容', () {
      final md = buildConversationMarkdown([
        AssistantMessage(role: 'user', text: '敏感问题'),
        AssistantMessage(role: 'ai', text: '...', blocked: true),
      ]);

      expect(md, contains('（内容已被安全限制）'));
    });

    test('AI 题卡经 cardPlainText 一并导出', () {
      final md = buildConversationMarkdown([
        AssistantMessage(
          role: 'ai',
          text: '这道题试试：',
          cards: [
            AssistantCard(
              kind: AssistantCardKind.question,
              subject: '数学',
            ),
          ],
        ),
      ]);

      expect(md, contains('【题目】'));
    });

    test('空对话返回空态提示，不崩', () {
      final md = buildConversationMarkdown(const <AssistantMessage>[]);
      expect(md, contains('（暂无内容）'));
    });
  });
}
