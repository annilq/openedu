import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'network_service.dart';

/// 一条 SSE 事件：事件名 + 解析后的 data 对象。
///
/// 与后端 ADR-0015 信封对齐：事件名为 `token` / `question` / `safety_refusal`
/// / `done` / `error`，data 为 JSON 对象。
class SseEvent {
  final String event;
  final Map<String, dynamic> data;

  const SseEvent(this.event, this.data);
}

/// SSE 客户端：把后端的 text/event-stream 字节流解析为本项目信封事件。
///
/// 复用 [NetworkService]（Dio 实现），自动获得 Token 注入与错误统一；
/// 非 2xx 由 Dio 拦截器转 [AppException] 抛出，业务错误走 `error` 事件。
class SseClient {
  final NetworkService _network;

  const SseClient(this._network);

  /// 发起一次流式 POST，按 SSE 协议逐事件产出。
  Stream<SseEvent> stream(String path, {Map<String, dynamic>? body}) {
    return _parse(_network.streamPost(path, body: body));
  }

  static Stream<SseEvent> _parse(Stream<Uint8List> bytes) async* {
    var buffer = '';
    await for (final chunk in bytes) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      // 归一化换行，避免 CRLF / LF 混用导致边界误判。
      buffer = buffer.replaceAll('\r\n', '\n');
      var sep = buffer.indexOf('\n\n');
      while (sep != -1) {
        final raw = buffer.substring(0, sep);
        buffer = buffer.substring(sep + 2);
        final ev = _parseEvent(raw);
        if (ev != null) yield ev;
        sep = buffer.indexOf('\n\n');
      }
    }
    // 连接结束但末尾未带空行：补解析残留。
    if (buffer.trim().isNotEmpty) {
      final ev = _parseEvent(buffer);
      if (ev != null) yield ev;
    }
  }

  static SseEvent? _parseEvent(String raw) {
    String? event;
    final dataLines = <String>[];
    for (final line in raw.split('\n')) {
      final l = line.trim();
      if (l.startsWith('event:')) {
        event = l.substring(6).trim();
      } else if (l.startsWith('data:')) {
        dataLines.add(l.substring(5).trim());
      }
    }
    if (event == null || dataLines.isEmpty) return null;
    final dataStr = dataLines.join('\n');
    final data = jsonDecode(dataStr) as Map<String, dynamic>;
    return SseEvent(event, data);
  }
}
