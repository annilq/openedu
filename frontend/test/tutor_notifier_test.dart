import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/assistant/data/assistant_api_client.dart';
import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/tutor/presentation/providers/tutor_notifier.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/presentation/resource.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/exceptions/app_exception.dart';

/// 日志 / 用量现在是 [Resource] 加载器，测试按同样的形状构造即可。
ParamResourceNotifier<List<TutorLogModel>, String> _logsNotifier(
        NetworkService network) =>
    ParamResourceNotifier(
      network,
      pathOf: (_) => '/tutor/logs',
      queryOf: (childId) => {'child_id': childId},
      parse: (d) => decodeList(d, TutorLogModel.fromJson),
    );

ParamResourceNotifier<TutorUsageModel, String> _usageNotifier(
        NetworkService network) =>
    ParamResourceNotifier(
      network,
      pathOf: (_) => '/tutor/usage',
      queryOf: (childId) => {'child_id': childId},
      parse: (d) => TutorUsageModel.fromJson(decodeMap(d)),
    );

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
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Stream<Uint8List> streamPost(String path, {Map<String, dynamic>? body}) =>
      const Stream<Uint8List>.empty();
}

/// 假 AssistantApiClient：按预设逐帧产出 AG-UI 事件（统一 /assistant/chat 协议）。
class _FakeAssistant extends Fake implements AssistantApiClient {
  _FakeAssistant({this.events = const []});
  final List<AssistantEvent> events;

  @override
  Stream<AssistantEvent> streamChat(AssistantChatReq req) =>
      Stream.fromIterable(events);
}

/// 假 AssistantApiClient：在 done 完成前保持流挂起（测试防重入）。
class _PendingAssistant extends Fake implements AssistantApiClient {
  final Completer<void> done = Completer<void>();

  @override
  Stream<AssistantEvent> streamChat(AssistantChatReq req) async* {
    await done.future;
    yield AssistantEvent(
      eventType: AssistantEventType.assistantMessage,
      text: '先算个位，结果是 68。',
    );
  }
}

/// 假 AssistantApiClient：streamChat 直接抛 AppException（模拟非 2xx）。
class _ThrowingAssistant extends Fake implements AssistantApiClient {
  _ThrowingAssistant(this._error);
  final AppException _error;

  @override
  Stream<AssistantEvent> streamChat(AssistantChatReq req) =>
      Stream.error(_error);
}

void main() {
  group('TutorNotifier（统一 /assistant/chat 流式，ADR-0024）', () {
    test('ask 流式 ASSISTANT_MESSAGE 累加到 AI 气泡', () async {
      final assistant = _FakeAssistant(events: [
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '先算个位',
        ),
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '，结果是 68。',
        ),
      ]);
      final notifier = TutorNotifier(assistant);

      await notifier.ask(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '加法',
        question: '23 + 45 怎么算',
      ));

      final state = notifier.state;
      expect(state, isA<TutorLoaded>());
      final loaded = state as TutorLoaded;
      expect(loaded.messages.length, 2);
      expect(loaded.messages[0].role, 'child');
      expect(loaded.messages[0].text, '23 + 45 怎么算');
      expect(loaded.messages[1].role, 'ai');
      expect(loaded.messages[1].text, '先算个位，结果是 68。');
      expect(loaded.messages[1].blocked, isFalse);
    });

    test('ask 接口异常时保留历史气泡并提示重试', () async {
      final notifier = TutorNotifier(
        _ThrowingAssistant(AppException('网络错误，请稍后重试')),
      );

      await notifier.ask(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '加法',
        question: '1+1',
      ));

      final loaded = notifier.state as TutorLoaded;
      expect(loaded.messages.length, 2);
      expect(loaded.messages.last.text, contains('网络错误'));
    });

    test('提交中重复点击被忽略（防重入）', () async {
      final assistant = _PendingAssistant();
      final notifier = TutorNotifier(assistant);

      // 第一次未 await 完成即第二次调用，应只产生一次请求 / 一条娃娃气泡
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
      expect(notifier.state, isA<TutorLoading>());

      assistant.done.complete();
      await Future.wait([f1, f2]);

      final loaded = notifier.state as TutorLoaded;
      expect(loaded.messages.where((m) => m.role == 'child').length, 1);
      expect(loaded.messages.first.text, '第一问');
    });

    test('INPUT_UNSAFE 错误标记 blocked', () async {
      final assistant = _FakeAssistant(events: [
        AssistantEvent(
          eventType: AssistantEventType.error,
          code: 'INPUT_UNSAFE',
          message: '输入含不安全内容',
        ),
        AssistantEvent(
          eventType: AssistantEventType.assistantMessage,
          text: '这个问题我没法回答哦。',
        ),
      ]);
      final notifier = TutorNotifier(assistant);

      await notifier.ask(TutorAskReq(
        subject: '科学',
        grade: 3,
        knowledgePoint: '',
        question: '暴力相关内容',
      ));

      final loaded = notifier.state as TutorLoaded;
      expect(loaded.messages.last.blocked, isTrue);
    });

    test('服务端业务错误（429）透出提示文案', () async {
      final notifier = TutorNotifier(_ThrowingAssistant(
        AppException('今日 AI 答疑次数已达上限（50 次），明日再来哦～',
            statusCode: 429),
      ));
      await notifier.ask(TutorAskReq(
        subject: '英语',
        grade: 2,
        knowledgePoint: '',
        question: 'hi',
      ));

      final loaded = notifier.state as TutorLoaded;
      expect(loaded.messages.last.text, contains('上限'));
      expect(loaded.messages.last.text, isNot(contains('网络异常')));
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
      final notifier = _logsNotifier(network);

      await notifier.load('c1');

      expect(network.getPaths.single, '/tutor/logs');
      final logs = notifier.state.dataOrNull!;
      expect(logs.length, 1);
      expect(logs.first.question, '23+45 怎么算');
      expect(logs.first.blocked, isFalse);
    });

    test('load 异常进入 Error 状态', () async {
      final notifier = _logsNotifier(_ThrowingNetwork());
      await notifier.load('c1');
      expect(notifier.state, isA<ResourceError>());
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
      // child_id 走 query 参数（非 body）
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
      final notifier = _usageNotifier(network);

      await notifier.load('c1');

      expect(network.getPaths.single, '/tutor/usage');
      final usage = notifier.state.dataOrNull!;
      expect(usage.asksToday, 3);
      expect(usage.usedSeconds, 127);
      expect(usage.askLimit, 9);
      expect(usage.minutesLimit, 30);
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
      final notifier = _logsNotifier(network);

      expect(notifier.state, isA<ResourceIdle>());
      final future = notifier.load('c1');
      expect(notifier.state, isA<ResourceLoading>());
      await future;

      final logs = notifier.state.dataOrNull!;
      expect(logs.length, 1);
      expect(logs.first.question, 'q');
    });

    test('TutorLogsNotifier: Error 态', () async {
      final network = MockNetworkService();
      when(() => network.get('/tutor/logs', query: any(named: 'query')))
          .thenThrow(Exception('boom'));
      final notifier = _logsNotifier(network);

      await notifier.load('c1');

      expect(notifier.state, isA<ResourceError>());
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
      final notifier = _usageNotifier(network);

      expect(notifier.state, isA<ResourceIdle>());
      final future = notifier.load('c1');
      expect(notifier.state, isA<ResourceLoading>());
      await future;

      final usage = notifier.state.dataOrNull!;
      expect(usage.asksToday, 2);
      expect(usage.minutesLimit, 30);
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
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Stream<Uint8List> streamPost(String path, {Map<String, dynamic>? body}) =>
      const Stream<Uint8List>.empty();
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
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Stream<Uint8List> streamPost(String path, {Map<String, dynamic>? body}) =>
      const Stream<Uint8List>.empty();
}
