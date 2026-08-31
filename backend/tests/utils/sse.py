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
