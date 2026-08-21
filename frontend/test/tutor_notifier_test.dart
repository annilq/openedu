import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/tutor/presentation/providers/tutor_notifier.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/exceptions/app_exception.dart';

/// mocktail 假网络：按 stub 返回/抛错，可 verify 调用次数。
class MockNetworkService extends Mock implements NetworkService {}

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
  Future<dynamic> put(String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? body}) async =>
      null;

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

    test('服务端业务错误（429/403）透出提示文案', () async {
      final notifier = TutorNotifier(_BusinessErrorNetwork());
      await notifier.ask(TutorAskReq(
        subject: '英语',
        grade: 2,
        knowledgePoint: '',
        question: 'hi',
      ));

      final state = notifier.state as TutorLoaded;
      expect(state.messages.last.text, contains('明日再来'));
      expect(state.messages.last.text, isNot(contains('网络异常')));
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

  group('TutorQuotaNotifier（T10 AI 使用管控）', () {
    test('load 命中 /tutor/quota 并解析配置', () async {
      final network = FakePutNetwork(getResponses: {
        '/tutor/quota': {
          'child_id': 'c1',
          'daily_ask_limit': 10,
          'daily_minutes_limit': 20,
          'allowed_subjects': ['数学', '语文'],
        },
      });
      final notifier = TutorQuotaNotifier(network);

      await notifier.load(childId: 'c1');

      expect(network.getPaths.single, '/tutor/quota');
      final state = notifier.state as TutorQuotaLoaded;
      expect(state.quota.dailyAskLimit, 10);
      expect(state.quota.dailyMinutesLimit, 20);
      expect(state.quota.allowedSubjects, ['数学', '语文']);
    });

    test('save 发送 PUT body（整体覆盖，null 字段显式传）', () async {
      final network = FakePutNetwork(putResponse: {
        'child_id': 'c1',
        'daily_ask_limit': 5,
        'daily_minutes_limit': null,
        'allowed_subjects': ['数学'],
      });
      final notifier = TutorQuotaNotifier(network);

      final error = await notifier.save(
        childId: 'c1',
        req: TutorQuotaUpdateReq(dailyAskLimit: 5, allowedSubjects: ['数学']),
      );

      expect(error, isNull);
      final call = network.putCalls.single;
      expect(call.$1, '/tutor/quota');
      expect(call.$2?['child_id'], 'c1');
      expect(call.$3?['daily_ask_limit'], 5);
      expect(call.$3?['daily_minutes_limit'], isNull);
      expect(call.$3?['allowed_subjects'], ['数学']);
      // 保存成功进入 Loaded
      expect(notifier.state, isA<TutorQuotaLoaded>());
    });

    test('save 业务校验失败返回错误文案不抛异常', () async {
      final network = FakePutNetwork(
        putResponse: null,
        putError: HttpException('不支持的学科：物理', statusCode: 422),
      );
      final notifier = TutorQuotaNotifier(network);

      final error = await notifier.save(
        childId: 'c1',
        req: TutorQuotaUpdateReq(allowedSubjects: ['物理']),
      );

      expect(error, contains('物理'));
      expect(notifier.state, isA<TutorQuotaInitial>());
    });
  });

  group('TutorUsageNotifier（T10 当日用量）', () {
    test('load 命中 /tutor/usage 并解析用量与生效限额', () async {
      final network = FakePutNetwork(getResponses: {
        '/tutor/usage': {
          'child_id': 'c1',
          'date': '2026-08-20',
          'asks_today': 3,
          'used_seconds': 127,
          'ask_limit': 9,
          'minutes_limit': 30,
          'allowed_subjects': ['数学'],
        },
      });
      final notifier = TutorUsageNotifier(network);

      await notifier.load(childId: 'c1');

      expect(network.getPaths.single, '/tutor/usage');
      final state = notifier.state as TutorUsageLoaded;
      expect(state.usage.asksToday, 3);
      expect(state.usage.usedSeconds, 127);
      expect(state.usage.askLimit, 9);
      expect(state.usage.minutesLimit, 30);
    });
  });

  group('TutorNotifier 状态机（mocktail）', () {
    test('Idle → Loading → Loaded（成功迁移）', () async {
      final network = MockNetworkService();
      final completer = Completer<dynamic>();
      when(() => network.post('/tutor/ask', body: any(named: 'body')))
          .thenAnswer((_) => completer.future);
      final notifier = TutorNotifier(network);

      expect(notifier.state, isA<TutorInitial>());

      final future = notifier.ask(TutorAskReq(
          subject: '数学', grade: 2, knowledgePoint: '', question: '1+1'));
      // 同步进入 Loading，娃娃气泡即时上屏
      final loading = notifier.state as TutorLoading;
      expect(loading.messages.length, 1);
      expect(loading.messages.first.role, 'child');

      completer.complete(
          {'answer': '答案是 2', 'blocked': false, 'reason': null});
      await future;

      final loaded = notifier.state as TutorLoaded;
      expect(loaded.messages.length, 2);
      expect(loaded.messages.last.text, '答案是 2');
      verify(() => network.post('/tutor/ask', body: any(named: 'body')))
          .called(1);
    });

    test('Idle → Loading → Loaded（AppException 透出提示文案）', () async {
      final network = MockNetworkService();
      when(() => network.post('/tutor/ask', body: any(named: 'body')))
          .thenThrow(HttpException(
              '今日 AI 答疑次数已达上限（50 次），明日再来哦～',
              statusCode: 429));
      final notifier = TutorNotifier(network);

      await notifier.ask(
          TutorAskReq(subject: '数学', grade: 2, knowledgePoint: '', question: 'hi'));

      final loaded = notifier.state as TutorLoaded;
      expect(loaded.messages.last.text, contains('上限'));
      expect(loaded.messages.last.text, isNot(contains('网络异常')));
    });

    test('Loading 期间重复 ask 被忽略（防重入，仅一次请求）', () async {
      final network = MockNetworkService();
      final completer = Completer<dynamic>();
      when(() => network.post('/tutor/ask', body: any(named: 'body')))
          .thenAnswer((_) => completer.future);
      final notifier = TutorNotifier(network);

      final f1 = notifier.ask(TutorAskReq(
          subject: '数学', grade: 2, knowledgePoint: '', question: '第一问'));
      final f2 = notifier.ask(TutorAskReq(
          subject: '数学', grade: 2, knowledgePoint: '', question: '第二问'));

      expect(notifier.state, isA<TutorLoading>());
      completer.complete(
          {'answer': 'ok', 'blocked': false, 'reason': null});
      await Future.wait([f1, f2]);

      final loaded = notifier.state as TutorLoaded;
      // 只有第一问上屏、只发一次请求
      expect(loaded.messages.where((m) => m.role == 'child').length, 1);
      verify(() => network.post('/tutor/ask', body: any(named: 'body')))
          .called(1);
    });
  });

  group('日志/管控/用量 notifier 四态（mocktail）', () {
    test('TutorLogsNotifier: Initial → Loading → Loaded', () async {
      final network = MockNetworkService();
      when(() => network.get('/tutor/logs', query: any(named: 'query')))
          .thenAnswer((_) async => [
                {
                  'id': 'l1',
                  'grade': 2,
                  'subject': '数学',
                  'knowledge_point': '',
                  'question': 'q',
                  'answer': 'a',
                  'input_safe': true,
                  'output_safe': true,
                  'blocked': false,
                  'created_at': '2026-08-20T10:00:00',
                },
              ]);
      final notifier = TutorLogsNotifier(network);

      expect(notifier.state, isA<TutorLogsInitial>());
      final future = notifier.load(childId: 'c1');
      expect(notifier.state, isA<TutorLogsLoading>());
      await future;

      final loaded = notifier.state as TutorLogsLoaded;
      expect(loaded.logs.length, 1);
      expect(loaded.logs.first.question, 'q');
    });

    test('TutorLogsNotifier: Error 态', () async {
      final network = MockNetworkService();
      when(() => network.get('/tutor/logs', query: any(named: 'query')))
          .thenThrow(Exception('boom'));
      final notifier = TutorLogsNotifier(network);

      await notifier.load(childId: 'c1');

      expect(notifier.state, isA<TutorLogsError>());
    });

    test('TutorQuotaNotifier: Initial → Loading → Loaded', () async {
      final network = MockNetworkService();
      when(() => network.get('/tutor/quota', query: any(named: 'query')))
          .thenAnswer((_) async => {
                'child_id': 'c1',
                'daily_ask_limit': 10,
                'daily_minutes_limit': null,
                'allowed_subjects': ['数学'],
              });
      final notifier = TutorQuotaNotifier(network);

      expect(notifier.state, isA<TutorQuotaInitial>());
      final future = notifier.load(childId: 'c1');
      expect(notifier.state, isA<TutorQuotaLoading>());
      await future;

      final loaded = notifier.state as TutorQuotaLoaded;
      expect(loaded.quota.dailyAskLimit, 10);
    });

    test('TutorUsageNotifier: Initial → Loading → Loaded', () async {
      final network = MockNetworkService();
      when(() => network.get('/tutor/usage', query: any(named: 'query')))
          .thenAnswer((_) async => {
                'child_id': 'c1',
                'date': '2026-08-21',
                'asks_today': 2,
                'used_seconds': 60,
                'ask_limit': 9,
                'minutes_limit': 30,
                'allowed_subjects': null,
              });
      final notifier = TutorUsageNotifier(network);

      expect(notifier.state, isA<TutorUsageInitial>());
      final future = notifier.load(childId: 'c1');
      expect(notifier.state, isA<TutorUsageLoading>());
      await future;

      final loaded = notifier.state as TutorUsageLoaded;
      expect(loaded.usage.asksToday, 2);
      expect(loaded.usage.minutesLimit, 30);
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
  Future<dynamic> put(String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? body}) async =>
      null;

  @override
  Future<dynamic> delete(String path) async => null;
}

/// post 抛业务异常（如 429 上限）的假网络：验证提示文案透出。
class _BusinessErrorNetwork implements NetworkService {
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => null;

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    throw HttpException('今日 AI 答疑次数已达上限（50 次），明日再来哦～',
        statusCode: 429);
  }

  @override
  Future<dynamic> put(String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? body}) async =>
      null;

  @override
  Future<dynamic> delete(String path) async => null;
}

/// 支持 GET 预置响应 + PUT 记录/预置响应的假网络（quota/usage 用）。
class FakePutNetwork implements NetworkService {
  final Map<String, dynamic> getResponses;
  final Map<String, dynamic>? putResponse;
  final Object? putError;
  final List<String> getPaths = [];
  // (path, query, body)
  final List<(String, Map<String, dynamic>?, Map<String, dynamic>?)> putCalls =
      [];

  FakePutNetwork({this.getResponses = const {}, this.putResponse, this.putError});

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    getPaths.add(path);
    return getResponses[path];
  }

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Future<dynamic> put(String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? body}) async {
    putCalls.add((path, query, body));
    if (putError != null) throw putError!;
    return putResponse;
  }

  @override
  Future<dynamic> delete(String path) async => null;
}
