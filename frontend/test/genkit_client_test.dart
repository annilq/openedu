import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/client.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/tutor/presentation/providers/tutor_notifier.dart';
import 'package:kids_learn/features/home/presentation/providers/home_notifier.dart';
import 'package:kids_learn/shared/data/remote/genkit_ai_client.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';

/// 不经网络的假 NetworkService：askStream / preview 走 Genkit client，不触网，
/// 仅用于满足 TutorNotifier / TaskGenNotifier 的构造签名。
class _NoopNetwork implements NetworkService {
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => null;
  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async => null;
  @override
  Future<dynamic> put(String path,
          {Map<String, dynamic>? query, Map<String, dynamic>? body}) async =>
      null;
  @override
  Future<dynamic> delete(String path) async => null;
  @override
  Stream<Uint8List> streamPost(String path, {Map<String, dynamic>? body}) =>
      const Stream<Uint8List>.empty();
}

/// 假 GenkitAiClient：不经网络，直接返回构造好的**原生 ActionStream**
/// （逐 chunk 推送 + 末帧 onResult），用于验证前端 askStream / preview 对
/// Genkit 原生协议（08b 统一）的解析。
///
/// 注：`ActionStream(onResult, Stream<S>)` 使用 `package:genkit/client.dart` 的
/// 公共构造；若后续 genkit 版本调整构造签名，`flutter analyze` 会提示，按新版
/// 调整此处即可（不影响被测业务逻辑的断言）。
class _FakeGenkit extends Fake implements GenkitAiClient {
  final List<String> tutorChunks;
  final TutorReply tutorResult;
  final List<TaskGenChunk> taskChunks;
  final List<QuestionPreview> taskResult;

  Map<String, dynamic>? lastTutorInput;
  Map<String, dynamic>? lastTasksInput;

  _FakeGenkit({
    this.tutorChunks = const ['先算个位', '，再算十位', '，结果是 68。'],
    this.tutorResult =
        const TutorReply(text: '先算个位，再算十位，结果是 68。', blocked: false),
    this.taskChunks = const [],
    this.taskResult = const [],
  });

  @override
  ActionStream<String, TutorReply> streamTutor(Map<String, dynamic> input) {
    lastTutorInput = input;
    return ActionStream<String, TutorReply>(
      Future.value(tutorResult),
      Stream.fromIterable(tutorChunks),
    );
  }

  @override
  ActionStream<TaskGenChunk, List<QuestionPreview>> streamTasks(
      Map<String, dynamic> input) {
    lastTasksInput = input;
    return ActionStream<TaskGenChunk, List<QuestionPreview>>(
      Future.value(taskResult),
      Stream.fromIterable(taskChunks),
    );
  }
}

void main() {
  group('Genkit AiClient 原生协议解析（08b 统一）', () {
    test('askStream：逐 token 累加成 AI 气泡，onResult 补 blocked 打标', () async {
      final notifier = TutorNotifier(_NoopNetwork(), _FakeGenkit());

      await notifier.askStream(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '加法',
        question: '23 + 45 怎么算',
      ));

      final state = notifier.state;
      expect(state, isA<TutorLoaded>());
      final loaded = state as TutorLoaded;
      // 娃娃问 + AI 答 两气泡
      expect(loaded.messages.length, 2);
      expect(loaded.messages[0].role, 'child');
      expect(loaded.messages[0].text, '23 + 45 怎么算');
      expect(loaded.messages[1].role, 'ai');
      // 流式 chunk 拼接
      expect(loaded.messages[1].text, '先算个位，再算十位，结果是 68。');
      // 末帧 onResult 的 blocked 落标
      expect(loaded.messages[1].blocked, isFalse);
    });

    test('askStream：请求体 snake_case 与后端契约对齐', () async {
      final fake = _FakeGenkit();
      final notifier = TutorNotifier(_NoopNetwork(), fake);

      await notifier.askStream(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '加法',
        question: '23 + 45 怎么算',
      ));

      expect(fake.lastTutorInput, isNotNull);
      expect(fake.lastTutorInput!['subject'], '数学');
      expect(fake.lastTutorInput!['grade'], 2);
      expect(fake.lastTutorInput!['knowledge_point'], '加法');
      expect(fake.lastTutorInput!['question'], '23 + 45 怎么算');
    });

    test('askStream：安全兜底 onResult.blocked=true 透传打标', () async {
      final notifier = TutorNotifier(
        _NoopNetwork(),
        _FakeGenkit(
          tutorChunks: const ['这个问题不能回答哦'],
          tutorResult:
              const TutorReply(text: '这个问题不能回答哦', blocked: true),
        ),
      );

      await notifier.askStream(TutorAskReq(
        subject: '数学',
        grade: 2,
        knowledgePoint: '',
        question: '怎么作弊',
      ));

      final loaded = notifier.state as TutorLoaded;
      expect(loaded.messages.last.blocked, isTrue);
    });

    test('preview：逐题卡浮现，onResult 整卷落定（streaming=false）', () async {
      final cards = [
        QuestionPreview(
          subject: '数学',
          grade: 2,
          stem: '1+1=',
          qtype: 'calc',
          knowledgePoint: '加法',
          explanation: '等于 2',
        ),
        QuestionPreview(
          subject: '语文',
          grade: 2,
          stem: '拼音题',
          qtype: 'fill',
          knowledgePoint: '拼音',
        ),
        QuestionPreview(
          subject: '英语',
          grade: 2,
          stem: 'apple 中文',
          qtype: 'open',
          knowledgePoint: '词汇',
        ),
      ];
      final notifier = TaskGenNotifier(
        _NoopNetwork(),
        _FakeGenkit(
          taskChunks: cards.map((q) => CardChunk(0, q)).toList(),
          taskResult: cards,
        ),
      );

      await notifier.preview(
        childId: 'c1',
        title: '混合卷',
        specs: [
          TaskSpecModel(
            subject: '数学',
            grade: 2,
            knowledgePoint: '加法',
            qtype: 'calc',
            count: 1,
          ),
        ],
      );

      final state = notifier.state;
      expect(state, isA<TaskGenPreview>());
      final preview = state as TaskGenPreview;
      expect(preview.streaming, isFalse);
      expect(preview.questions.length, 3);
      expect(preview.questions[0].stem, '1+1=');
      expect(preview.questions[2].subject, '英语');
    });

    test('preview：请求体含 child_id / specs（snake_case）', () async {
      final fake = _FakeGenkit(taskChunks: const [], taskResult: const []);
      final notifier = TaskGenNotifier(_NoopNetwork(), fake);

      await notifier.preview(
        childId: 'c1',
        title: '空卷',
        specs: [
          TaskSpecModel(
            subject: '数学',
            grade: 2,
            knowledgePoint: '加法',
            qtype: 'calc',
            count: 2,
          ),
        ],
      );

      expect(fake.lastTasksInput, isNotNull);
      expect(fake.lastTasksInput!['child_id'], 'c1');
      expect(fake.lastTasksInput!['title'], '空卷');
      final specs = fake.lastTasksInput!['specs'] as List;
      expect(specs.length, 1);
      expect(specs.first['knowledge_point'], '加法');
      expect(specs.first['count'], 2);
    });

    test('preview：空卷 onResult 空列表，仍进入 TaskGenPreview', () async {
      final notifier = TaskGenNotifier(
        _NoopNetwork(),
        _FakeGenkit(taskChunks: const [], taskResult: const []),
      );

      await notifier.preview(
        childId: 'c1',
        title: '空卷',
        specs: const [],
      );

      final preview = notifier.state as TaskGenPreview;
      expect(preview.streaming, isFalse);
      expect(preview.questions, isEmpty);
    });
  });
}
