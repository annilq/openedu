import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/features/tutor/presentation/providers/tutor_notifier.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';

/// 模拟 NetworkService：用给定 SSE 文本流驱动 [TutorNotifier.askStream]。
class _SseFakeNetwork implements NetworkService {
  final String sse;
  _SseFakeNetwork(this.sse);

  @override
  Stream<Uint8List> streamPost(String path, {Map<String, dynamic>? body}) =>
      Stream<Uint8List>.value(utf8.encode(sse));

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      throw UnimplementedError();
  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) =>
      throw UnimplementedError();
  @override
  Future<dynamic> put(String path,
          {Map<String, dynamic>? query, Map<String, dynamic>? body}) =>
      throw UnimplementedError();
  @override
  Future<dynamic> delete(String path) => throw UnimplementedError();
}

TutorAskReq _req() => TutorAskReq(
      subject: '数学',
      grade: 2,
      knowledgePoint: '加法',
      question: '1+1 等于几？',
    );

void main() {
  group('TutorNotifier.askStream', () {
    test('appends tokens then settles into TutorLoaded', () async {
      const sse = 'event: token\ndata: {"text":"你好"}\n\n'
          'event: token\ndata: {"text":"，世界"}\n\n'
          'event: done\ndata: {"usage":{"seconds":1}}\n\n';
      final n = TutorNotifier(_SseFakeNetwork(sse));
      await n.askStream(_req());
      expect(n.state, isA<TutorLoaded>());
      final loaded = n.state as TutorLoaded;
      expect(loaded.messages, hasLength(2));
      expect(loaded.messages[0].role, 'child');
      expect(loaded.messages[1].role, 'ai');
      expect(loaded.messages[1].text, '你好，世界');
      expect(loaded.messages[1].blocked, isFalse);
    });

    test('safety_refusal -> blocked bubble, raw text never rendered', () async {
      const sse = 'event: safety_refusal\ndata: {"reason":"这个问题不能回答"}\n\n'
          'event: done\ndata: {"usage":{"seconds":0}}\n\n';
      final n = TutorNotifier(_SseFakeNetwork(sse));
      await n.askStream(_req());
      final loaded = n.state as TutorLoaded;
      expect(loaded.messages.last.blocked, isTrue);
      expect(loaded.messages.last.text, contains('🛡️'));
    });

    test('error event -> error bubble, settles', () async {
      const sse = 'event: error\ndata: {"message":"模型服务暂不可用"}\n\n';
      final n = TutorNotifier(_SseFakeNetwork(sse));
      await n.askStream(_req());
      final loaded = n.state as TutorLoaded;
      expect(loaded.messages.last.text, contains('⚠️'));
    });
  });
}
