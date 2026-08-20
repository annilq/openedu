import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/tutor/presentation/providers/tutor_notifier.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';

/// 内存版 NetworkService：按 path 返回预置响应，记录 POST body。
class FakeNetwork implements NetworkService {
  final Map<String, dynamic> responses;
  final List<Map<String, dynamic>> postBodies = [];
  final List<String> getPaths = [];
  FakeNetwork({required this.responses});

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    getPaths.add(path);
    return responses[path];
  }

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    postBodies.add(body ?? {});
    return {
      'answer': '先算个位，再算十位，结果是 68。',
      'blocked': false,
      'reason': null,
    };
  }

  @override
  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Future<dynamic> delete(String path) async => null;
}

void main() {
  group('TutorNotifier', () {
    test('ask 发送正确 body 并拼接娃娃/AI 气泡', () async {
      final network = FakeNetwork(responses: {});
      final notifier = TutorNotifier(network);

      await notifier.ask(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '加法',
        question: '23 + 45 怎么算',
      ));

      // 请求体字段对齐后端契约（snake_case）
      final body = network.postBodies.single;
      expect(body['subject'], '数学');
      expect(body['grade'], 2);
      expect(body['knowledge_point'], '加法');
      expect(body['question'], '23 + 45 怎么算');

      final state = notifier.state;
      expect(state, isA<TutorLoaded>());
      final loaded = state as TutorLoaded;
      expect(loaded.messages.length, 2);
      expect(loaded.messages[0].role, 'child');
      expect(loaded.messages[0].text, '23 + 45 怎么算');
      expect(loaded.messages[1].role, 'ai');
      expect(loaded.messages[1].text, contains('68'));
      expect(loaded.messages[1].blocked, isFalse);
    });

    test('ask 接口异常时保留历史气泡并提示重试', () async {
      // post 抛错
      final notifier = TutorNotifier(_ThrowingNetwork());

      await notifier.ask(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '加法',
        question: '1+1',
      ));

      // 出错不再丢失上下文：保留娃娃气泡 + 错误提示气泡
      final state = notifier.state;
      expect(state, isA<TutorLoaded>());
      final loaded = state as TutorLoaded;
      expect(loaded.messages.length, 2);
      expect(loaded.messages.last.text, contains('网络异常'));
    });

    test('提交中重复点击被忽略（防重入）', () async {
      final network = FakeNetwork(responses: {});
      final notifier = TutorNotifier(network);

      // 第一次未 await 完成即第二次调用，应只产生一次请求
      final f1 = notifier.ask(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '加法',
        question: '第一问',
      ));
      final f2 = notifier.ask(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '加法',
        question: '第二问（应被忽略）',
      ));
      await Future.wait([f1, f2]);

      expect(network.postBodies.length, 1);
      expect(network.postBodies.single['question'], '第一问');
    });
  });

  group('TutorLogsNotifier', () {
    test('load 命中 /tutor/logs 并解析日志', () async {
      final network = FakeNetwork(responses: {
        '/tutor/logs': [
          {
            'id': 'l1',
            'grade': 2,
            'subject': '数学',
            'knowledge_point': '加法',
            'question': '23+45 怎么算',
            'answer': '先算个位…',
            'input_safe': true,
            'output_safe': true,
            'blocked': false,
            'created_at': '2026-08-20T10:00:00',
          }
        ],
      });
      final notifier = TutorLogsNotifier(network);

      await notifier.load(childId: 'c1');

      expect(network.getPaths.single, '/tutor/logs');
      final state = notifier.state;
      expect(state, isA<TutorLogsLoaded>());
      final loaded = state as TutorLogsLoaded;
      expect(loaded.logs.length, 1);
      expect(loaded.logs.first.question, '23+45 怎么算');
      expect(loaded.logs.first.blocked, isFalse);
    });

    test('load 异常进入 Error 状态', () async {
      final notifier = TutorLogsNotifier(_ThrowingNetwork());
      await notifier.load(childId: 'c1');
      expect(notifier.state, isA<TutorLogsError>());
    });
  });
}

/// 让 post/get 抛错的假网络。
class _ThrowingNetwork implements NetworkService {
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    throw Exception('network error');
  }

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    throw Exception('network error');
  }

  @override
  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Future<dynamic> delete(String path) async => null;
}
