"""SSE 响应解析工具（ADR-0015 流式端点测试用）。"""
from __future__ import annotations

import json


def parse_sse(text: str) -> list[tuple[str, dict]]:
    """把 SSE 文本解析为 [(event, data_dict), ...]。"""
    out: list[tuple[str, dict]] = []
    for block in text.split("\n\n"):
        block = block.strip()
        if not block:
            continue
        event = None
        data_lines: list[str] = []
        for line in block.splitlines():
            if line.startswith("event:"):
                event = line[len("event:") :].strip()
            elif line.startswith("data:"):
                data_lines.append(line[len("data:") :].strip())
        if event is None or not data_lines:
            continue
        data = json.loads("\n".join(data_lines))
        out.append((event, data))
    return out


def parse_genkit_sse(text: str) -> tuple[list, object | None]:
    """解析 Genkit 原生 SSE（`genkit_fastapi` serve_flow 格式）。

    逐帧：`data: {"message": <chunk>}`（流式增量）/ `data: {"result": <output>}`（末帧整体结果）；
    错误帧：`data: {"error": {...}}`（抛 AssertionError）。返回 (message_chunks, final_result)。
    """
    chunks: list = []
    result = None
    for raw in text.splitlines():
        line = raw.strip()
        # 流式错误帧：genkit Dart 客户端（client.dart）只认 `error: ` 前缀帧，
        # 服务端已据此把错误帧从 `data: {"error": ...}` 改为 `error: {...}`。
        if line.startswith("error: "):
            err_payload = line[len("error: "):].strip()
            obj = json.loads(err_payload)
            err = obj.get("error", obj)
            raise AssertionError(f"Genkit 错误帧：{err}")
        if not line.startswith("data:"):
            continue
        payload = line[len("data:"):].strip()
        if not payload:
            continue
        obj = json.loads(payload)
        if "error" in obj:
            raise AssertionError(f"Genkit 错误帧：{obj['error']}")
        if "message" in obj:
            chunks.append(obj["message"])
        elif "result" in obj:
            result = obj["result"]
    return chunks, result
