import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/assistant_card.dart';

/// [AssistantCard.fromData] 是线协议 → 领域对象的唯一入口（ADR-0042），
/// 它必须**容错**：字段缺、类型歪、后端加了新种类，都不能崩，
/// 也不能悄悄把内容吞掉（v1 就是只认 `{type, subject, stem}`，认不出即静默消失）。
void main() {
  group('AssistantCard.fromData · 正常载荷', () {
    test('kind 取自信封 type，其余字段取自 result', () {
      final card = AssistantCard.fromData({
        'type': 'wrong_question_list',
        'result': {
          'title': '错题',
          'subject': '小明（2年级）',
          'items': [
            {'subject': '数学', 'stem': '9+3=?', 'wrong_count': 2},
            {'subject': '语文', 'stem': '默写', 'wrong_count': 1},
          ],
          'total': 5,
        },
      })!;

      expect(card.kind, AssistantCardKind.wrongQuestionList);
      expect(card.title, '错题');
      expect(card.subject, '小明（2年级）');
      expect(card.items.length, 2);
      expect(card.items.last['stem'], '默写');
      expect(card.total, 5);
      expect(card.hasContent, isTrue);
    });

    test('progress 的 stats 与 question 的扁平载荷都原样可读', () {
      final progress = AssistantCard.fromData({
        'type': 'progress',
        'result': {
          'title': '学习进度',
          'stats': {'total': 4, 'correct': 3, 'accuracy': 0.75, 'streak_days': 2},
        },
      })!;
      expect(progress.stats['total'], 4);
      expect(progress.items, isEmpty);

      final question = AssistantCard.fromData({
        'type': 'question',
        'result': {
          'subject': '数学',
          'grade': 2,
          'qtype': 'choice',
          'stem': '1/2 + 1/2 = ?',
          'options': ['1', '1/2'],
        },
      })!;
      expect(question.kind, AssistantCardKind.question);
      // 题卡没有 title/text/items——靠 rawPayload 判定「有内容」。
      expect(question.title, isEmpty);
      expect(question.hasContent, isTrue);
      expect(question.rawPayload['options'], ['1', '1/2']);
    });
  });

  group('AssistantCard.fromData · interactive_scene（ADR-0061 决策 7）', () {
    test('外层 kind + 内层 scene kind 落 rawPayload，判定有内容', () {
      final card = AssistantCard.fromData(const {
        'type': 'interactive_scene',
        'result': {
          'kind': 'reflection',
          'title': '图形的运动（轴对称）',
          'inputs': [
            {'key': 'axisAngle', 'value': 90},
          ],
        },
      })!;

      expect(card.kind, AssistantCardKind.interactiveScene);
      expect(card.title, '图形的运动（轴对称）');
      // 内层场景类型与整份 SceneSpec 都原样可读，交给 SceneInterpreter 分派。
      expect(card.rawPayload['kind'], 'reflection');
      expect(card.hasContent, isTrue);
    });

    test('缺内层 kind → 视为无内容（不画空壳卡）', () {
      final card = AssistantCard.fromData(const {
        'type': 'interactive_scene',
        'result': {},
      })!;

      expect(card.kind, AssistantCardKind.interactiveScene);
      expect(card.hasContent, isFalse);
    });
  });

  group('AssistantCard.fromData · 题卡内联交互讲解（ADR-0061 消费方）', () {
    test('question 卡携带 scene_spec → 原样可读、判定有内容', () {
      final question = AssistantCard.fromData(const {
        'type': 'question',
        'result': {
          'subject': '数学',
          'grade': 4,
          'qtype': 'choice',
          'stem': '下面哪个图形是轴对称图形？',
          'options': ['A', 'B'],
          'scene_spec': {
            'kind': 'reflection',
            'title': '图形的运动（轴对称）',
            'inputs': [
              {'key': 'axisAngle', 'value': 90},
            ],
          },
        },
      })!;

      expect(question.kind, AssistantCardKind.question);
      // 题卡解析区据此内联渲染交互演示（assistant_question_card.dart）。
      expect(question.rawPayload['scene_spec'], isA<Map>());
      expect(question.rawPayload['scene_spec']['kind'], 'reflection');
      expect(question.hasContent, isTrue);
    });
  });

  group('AssistantCard.fromData · 容错', () {
    test('data 为 null / result 非对象 → 不产卡（畸形帧）', () {
      expect(AssistantCard.fromData(null), isNull);
      expect(AssistantCard.fromData(const {}), isNull);
      expect(
        AssistantCard.fromData(const {'type': 'notice', 'result': 'oops'}),
        isNull,
      );
    });

    test('字段类型歪掉不崩：数字给字符串、items 混入非对象', () {
      final card = AssistantCard.fromData(const {
        'type': 'task_list',
        'result': {
          'title': '今日任务',
          'total': '12',
          'items': [
            {'title': '计算 10 题', 'question_count': '10'},
            'not-a-map',
          ],
        },
      })!;

      expect(card.total, 12);
      expect(card.items.length, 1, reason: '非对象明细要被丢掉而不是崩');
      expect(card.items.single['question_count'], '10');
      expect(card.hasContent, isTrue);
    });

    test('未知种类 + 只有 unknown 字段 → 视为无内容（不画空壳）', () {
      final card = AssistantCard.fromData(const {
        'type': 'brand_new_kind',
        'result': {'whatever': 1},
      })!;

      expect(card.kind, 'brand_new_kind');
      expect(card.hasContent, isFalse);
    });
  });
}
