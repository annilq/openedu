import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/data/remote/sse_client.dart';

/// 模拟 NetworkService：用给定 SSE 文本流驱动 [SseClient.stream]。
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

void main() {
  group('SseClient.stream (ADR-0015 envelope)', () {
    test('parses event name and json data', () async {
      final events = await SseClient(_SseFakeNetwork(
        'event: token\ndata: {"text":"hi"}\n\n',
      )).stream('/x').toList();
      expect(events, hasLength(1));
      expect(events[0].event, 'token');
      expect(events[0].data, {'text': 'hi'});
    });

    test('event with no event line is skipped', () async {
      final events = await SseClient(_SseFakeNetwork(
        'data: {"text":"hi"}\n\n',
      )).stream('/x').toList();
      expect(events, isEmpty);
    });

    test('splits multiple events on blank lines', () async {
      const sse = 'event: token\ndata: {"text":"a"}\n\n'
          'event: done\ndata: {"usage":{"seconds":1}}\n\n';
      final events = await SseClient(_SseFakeNetwork(sse)).stream('/x').toList();
      expect(events, hasLength(2));
      expect(events[0].event, 'token');
      expect(events[0].data, {'text': 'a'});
      expect(events[1].event, 'done');
    });

    test('normalizes CRLF line endings', () async {
      final events = await SseClient(_SseFakeNetwork(
        'event: error\r\ndata: {"message":"x"}\r\n\r\n',
      )).stream('/x').toList();
      expect(events, hasLength(1));
      expect(events.single.event, 'error');
      expect(events.single.data, {'message': 'x'});
    });

    test('parses trailing event without trailing blank line', () async {
      final events = await SseClient(_SseFakeNetwork(
        'event: token\ndata: {"text":"z"}',
      )).stream('/x').toList();
      expect(events.single.data, {'text': 'z'});
    });
  });
}
