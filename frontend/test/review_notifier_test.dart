import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/review/data/repositories/review_repository_impl.dart';
import 'package:kids_learn/features/review/presentation/providers/review_notifier.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/presentation/paging.dart';

/// 内存版 NetworkService：按 path 返回预置响应，记录 POST body。
class FakeNetwork implements NetworkService {
  final Map<String, dynamic> responses;
  final List<Map<String, dynamic>> postBodies;
  FakeNetwork({required this.responses}) : postBodies = [];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    return responses[path];
  }

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    postBodies.add(body ?? {});
    return {
      'correct': true,
      'score': 100.0,
      'explanation': '解析：先算括号内',
    };
  }

  @override
  Future<dynamic> put(String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? body}) async =>
      null;

  @override
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Stream<Uint8List> streamPost(
    String path, {
    Map<String, dynamic>? body,
    Duration? receiveTimeout,
  }) =>
      const Stream<Uint8List>.empty();

  @override
  Future<Uint8List> postBytes(String path, {Map<String, dynamic>? body}) async =>
      throw UnimplementedError('本测试的替身不涉及二进制下载');
}

/// 后端游标信封（ADR-0053）；`next_cursor` 为 null 表示只有一页。
Map<String, dynamic> _page(List<Map<String, dynamic>> items) =>
    {'items': items, 'total': items.length, 'page_size': 20};

Map<String, dynamic> _reviewItemJson(String wrongId, {int stage = 1}) => {
      'wrong_question_id': wrongId,
      'question_id': 'q-$wrongId',
      'subject': '数学',
      'grade': 2,
      'knowledge_point': '两位数加减法',
      'qtype': 'calc',
      'stem': '23 + 45 = ?',
      'options': null,
      'explanation': '',
      'wrong_count': 2,
      'review_stage': stage,
      'next_interval_days': 4,
      'due_at': null,
    };

void main() {
  group('DueReviewNotifier', () {
    test('load 正确解析待复习队列', () async {
      final network = FakeNetwork(responses: {
        '/review/due': [_reviewItemJson('w1'), _reviewItemJson('w2')],
      });
      final notifier = DueReviewNotifier(ReviewRepositoryImpl(network));

      await notifier.load();

      final state = notifier.state;
      expect(state, isA<DueReviewLoaded>());
      final loaded = state as DueReviewLoaded;
      expect(loaded.items.length, 2);
      expect(loaded.items.first.wrongQuestionId, 'w1');
      expect(loaded.items.first.knowledgePoint, '两位数加减法');
      expect(loaded.items.first.nextIntervalDays, 4);
    });

    test('load 异常进入 Error 状态', () async {
      final network = FakeNetwork(responses: {
        '/review/due': 'not a list',
      });
      final notifier = DueReviewNotifier(ReviewRepositoryImpl(network));

      await notifier.load();

      expect(notifier.state, isA<DueReviewError>());
    });

    test('answer 答对：发送对应 body 并从队列移除该题', () async {
      final network = FakeNetwork(responses: {
        '/review/due': [_reviewItemJson('w1'), _reviewItemJson('w2')],
      });
      final notifier = DueReviewNotifier(ReviewRepositoryImpl(network));
      await notifier.load();

      final result = await notifier.answer('w1', '68');

      expect(result, isNotNull);
      expect(result!.correct, isTrue);
      expect(network.postBodies.single, {
        'wrong_question_id': 'w1',
        'student_answer': '68',
      });
      final state = notifier.state as DueReviewLoaded;
      expect(state.items.map((i) => i.wrongQuestionId), ['w2']);
    });

    test('answer 答错也移除该题（后端重置计时，下一轮到期再进队列）', () async {
      final wrongNetwork = _WrongAnswerNetwork();
      final n2 = DueReviewNotifier(ReviewRepositoryImpl(wrongNetwork));
      await n2.load();

      final result = await n2.answer('w1', '10');

      expect(result, isNotNull);
      expect(result!.correct, isFalse);
      expect(n2.state, isA<DueReviewLoaded>());
      expect((n2.state as DueReviewLoaded).items, isEmpty);
    });

    test('未加载时 answer 不请求且返回 null', () async {
      final network = FakeNetwork(responses: {});
      final notifier = DueReviewNotifier(ReviewRepositoryImpl(network));

      final result = await notifier.answer('w1', '68');

      expect(result, isNull);
      expect(network.postBodies, isEmpty);
    });
  });

  group('WrongQuestionsNotifier', () {
    Map<String, dynamic> wrongJson() => {
          'id': 'x1',
          'question_id': 'q1',
          'subject': '数学',
          'grade': 2,
          'knowledge_point': '乘法口诀',
          'qtype': 'calc',
          'stem': '7 × 8 = ?',
          'options': null,
          'answer': null, // 娃娃端不含答案
          'explanation': '',
          'wrong_count': 1,
          'first_wrong_at': '2026-08-20T00:00:00',
          'review_stage': 0,
          'due_at': '2026-08-21T00:00:00',
        };

    test('娃娃自查命中 /tasks/wrong-questions', () async {
      final network = FakeNetwork(responses: {
        '/tasks/wrong-questions': _page([wrongJson()]),
      });
      final notifier = PagingNotifier<WrongQuestionModel>(
        ({cursor}) => ReviewRepositoryImpl(network).childWrongQuestions(),
      );

      await notifier.load();

      final items = notifier.state.items;
      expect(items.length, 1);
      expect(items.first.answer, isNull);
      expect(items.first.wrongCount, 1);
    });

    test('家长查看命中 /tasks/children/{id}/wrong-questions 且含答案', () async {
      final network = FakeNetwork(responses: {
        '/tasks/children/c1/wrong-questions': _page([
          {...wrongJson(), 'answer': '56'},
        ]),
      });
      final notifier =
          ParamPagingNotifier<WrongQuestionModel, String>(
        (id, {cursor}) =>
            ReviewRepositoryImpl(network).parentWrongQuestions(id),
      );

      await notifier.load('c1');

      expect(notifier.state.items.single.answer, '56');
    });
  });

  group('掌握度模型解析', () {
    test('MasteryModel 解析字段', () {
      final json = {
        'child_id': 'c1',
        'total_knowledge_points': 2,
        'mastered_count': 1,
        'items': [
          {
            'knowledge_point': '两位数加减法',
            'subject': '数学',
            'grade': 2,
            'total_answers': 10,
            'correct_answers': 8,
            'accuracy': 0.8,
            'active_wrong': 0,
            'max_review_stage': 0,
            'score': 88.0,
            'level': '已掌握',
          },
          {
            'knowledge_point': '乘法口诀',
            'subject': '数学',
            'grade': 2,
            'total_answers': 6,
            'correct_answers': 3,
            'accuracy': 0.5,
            'active_wrong': 1,
            'max_review_stage': 2,
            'score': 60.0,
            'level': '薄弱',
          },
        ],
      };

      final model = MasteryModel.fromJson(json);

      expect(model.totalKnowledgePoints, 2);
      expect(model.masteredCount, 1);
      expect(model.items.first.level, '已掌握');
      expect(model.items.last.activeWrong, 1);
      expect(model.items.last.maxReviewStage, 2);
    });
  });
}

/// 复习答错场景：POST /review/answer 返回 correct=false。
class _WrongAnswerNetwork extends FakeNetwork {
  _WrongAnswerNetwork()
      : super(responses: {
          '/review/due': [
            {
              'wrong_question_id': 'w1',
              'question_id': 'q1',
              'subject': '数学',
              'grade': 2,
              'knowledge_point': '两位数加减法',
              'qtype': 'calc',
              'stem': '23 + 45 = ?',
              'options': null,
              'explanation': '',
              'wrong_count': 2,
              'review_stage': 0,
              'next_interval_days': 1,
              'due_at': null,
            }
          ],
        });

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    postBodies.add(body ?? {});
    return {'correct': false, 'score': 0.0, 'explanation': '再想想'};
  }
}
