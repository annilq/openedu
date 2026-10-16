# 01 · agent_core 流式 tool 扩展

## What to build

`ToolSpec` 加可选 `stream_handler`（async generator）；`run_with_tools` 支持流式 tool 分支。

- `agent_core/tools.py`：`ToolSpec` 增字段 `stream_handler: Callable[..., AsyncIterator[Any]] | None = None`；新增哨兵类 `ToolOutcome(data)`（回灌 content 载体）。
- `agent_core/subagent.py` `run_with_tools`：spec 有 `stream_handler` 时逐帧 yield（约定仅 THINKING / DATA / STEP / TOOL_CALL 中间帧），收到 `ToolOutcome` 后走既有 `tool_result` + 回灌 + `render_tool_result` 路径；流式分支内嵌在现有循环结构里，受同一 `max_turns` 与硬失败约束。
- 契约：流式 handler 不得产出 `ASSISTANT_MESSAGE`（收尾由 tool loop 第二轮做）；handler 异常按既有「单工具异常不应让整条流崩」处理（转 `{"error": ...}` 还是 error 帧，按流式特性定：帧已外发过的部分事实须保留，用 `{"error": ...}` 回灌 + 一条说明性 ERROR 前先 yield 已产帧）。
- 存量同步工具路径零变化（`handler` 非空时行为与现在逐字节一致）。

## Blocked by

无。

## 验收

- 新单测：流式 handler 的中间帧按序外发；`ToolOutcome.data` 成为回灌 content；流式中途抛异常不丢已发帧；同步工具路径既有测试全绿。
- `agent_core` 层无业务 import（AST 守卫或既有测试兜）。
