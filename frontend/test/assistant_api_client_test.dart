import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/features/assistant/data/assistant_api_client.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';

/// 按 path 返回预置 SSE 字节流的假 NetworkService，供解析逻辑单测。
class FakeSseNetwork implements NetworkService {
  FakeSseNetwork(this.streams);
  final Map<String, Stream<Uint8List>> streams;

  @override
  Stream<Uint8List> streamPost(String path, {Map<String, dynamic>? body}) =>
      streams[path] ?? const Stream<Uint8List>.empty();

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => null;
  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async => null;
  @override
  Future<dynamic> put(String path,
          {Map<String, dynamic>? query, Map<String, dynamic>? body}) async =>
      null;
  @override
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async => null;
}

/// 把事件 map 编码成一段 SSE 帧（含尾随 `\n\n`）。
List<int> _frame(Map<String, dynamic> m) =>
    utf8.encode('data: ${jsonEncode(m)}\n\n');

void main() {
  test('分帧解析：同块多帧 + 跨块切分都正确还原顺序', () async {
    final f1 = _frame({'eventType': 'THINKING', 'text': '在构思'});
    final f2 = _frame({'eventType': 'TOOL_CALL', 'tool': 'calc', 'label': '计算'});
    final f3 = _frame({'eventType': 'DONE', 'session_id': 'abc'});
    // 把第二帧从中间切开，验证缓冲跨块拼接
    final split = (f2.length / 2).round();
    final chunks = <Uint8List>[
      Uint8List.fromList([...f1, ...f2.sublist(0, split)]),
      Uint8List.fromList([...f2.sublist(split), ...f3]),
    ];
    final network = FakeSseNetwork({
      '/assistant/chat': Stream<Uint8List>.fromIterable(chunks),
    });
    final client = AssistantApiClient(network);

    final events = await client.streamChat(const AssistantChatReq(message: '23+45')).toList();

    expect(events.map((e) => e.eventType).toList(),
        ['THINKING', 'TOOL_CALL', 'DONE']);
    expect(events.last.sessionId, 'abc');
    expect(events[1].tool, 'calc');
  });

  test('末帧无尾随空行：缓冲区残留帧仍被解析', () async {
    // 故意不发送结尾的 `\n\n`，验证 stream 结束后对残留 buffer 的处理
    final f = _frame({'eventType': 'ASSISTANT_MESSAGE', 'text': '答案是68'});
    final noTrailer = f.sublist(0, f.length - 2); // 去掉末尾 \n\n
    final network = FakeSseNetwork({
      '/assistant/chat': Stream<Uint8List>.value(Uint8List.fromList(noTrailer)),
    });
    final client = AssistantApiClient(network);

    final events = await client.streamChat(const AssistantChatReq(message: 'hi')).toList();

    expect(events, hasLength(1));
    expect(events.single.eventType, 'ASSISTANT_MESSAGE');
    expect(events.single.text, '答案是68');
  });

  test('streamGenerate 与 streamChat 共用同一解析逻辑（ delegation，非复制）', () async {
    final f = _frame({'eventType': 'DATA', 'data': {'type': 'question', 'result': {'q': 1}}});
    final network = FakeSseNetwork({
      '/tasks/generate': Stream<Uint8List>.value(Uint8List.fromList(f)),
    });
    final client = AssistantApiClient(network);

    final events = await client
        .streamGenerate(const TaskGenerateReq(specs: []))
        .toList();

    expect(events, hasLength(1));
    expect(events.single.eventType, 'DATA');
    expect(events.single.data?['type'], 'question');
  });

  test('非法 data 帧被跳过，合法帧不受影响', () async {
    final bad = utf8.encode('data: not-json\n\n');
    final good = _frame({'eventType': 'DONE', 'session_id': 'ok'});
    final network = FakeSseNetwork({
      '/assistant/chat':
          Stream<Uint8List>.fromIterable([Uint8List.fromList(bad), Uint8List.fromList(good)]),
    });
    final client = AssistantApiClient(network);

    final events = await client.streamChat(const AssistantChatReq(message: 'x')).toList();

    expect(events, hasLength(1));
    expect(events.single.sessionId, 'ok');
  });
}
