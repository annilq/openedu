# ADR-0035 扩展钩子（extension seam，生命周期钩子）

> 决策日期：2026-09-14 ｜ 关联评审：`docs/agent-core-architecture-review.md` §4.2（P2 缺后台扩展钩子）

## 背景

架构评审 §4.2 指出：当前可扩展性全靠 `manifest.skill_prompt` 把 SOP 注入 system prompt（**LLM 可见**），
内核 grep `extension|hook|lifecycle` 零命中。需要「工具结果过大自动截断」「请求前注入租户级 system 约束」
「审计每轮 tool_call」这类 **LLM 不可见** 的干预点时，只能改内核或各 subagent，缺少统一挂载点。

参考 `pi-coding-agent` 有 `context` / `session_before_compact` / `tool_call` / `before_agent_start` 等
LLM 不可见钩子。据此在 `agent_core` 增加**可选** `Hooks` 接口。

## 决策

在 `agent_core`（业务无关的框架内核）落地一个可选、默认零行为的生命周期钩子 seam，固定三个挂载点：

- **`before_turn(turn, system, prompt, history) -> (system, prompt, history)`**（`agent_core/ports.py:142`）
  每轮 LLM 调用前触发，可改写系统/用户/历史后返回（如注入租户级约束）。
- **`after_tool(name, args, result, tool_call_id) -> result`**（`agent_core/ports.py:148`）
  工具执行后触发，返回改写后的 result 载荷（如截断超大 tool result）。
- **`rewrite_messages(messages) -> messages`**（`agent_core/ports.py:154`）
  发送前统一改写整段消息（如裁剪历史中的超大 tool result），仅用于本次请求、不写回 canonical history。

承载与透传：

- `agent_core/ports.py:125` `Hooks` 基类三个方法默认 no-op，业务继承后只覆写所需。
- `agent_core/ports.py:175` `RuntimeDeps.hooks: Hooks | None = None`，由业务层注入。
- `agent_core/subagent.py:116` `run_with_tools(agent, ..., hooks=None)` 在 tool loop 三处调用上述钩子。
- `agent_core/runtime.py:135` `AgentRuntime.run` 把 `deps.hooks` 透传到 `run_with_tools`。
- `agent_core/__init__.py` 已导出 `Hooks`，支持 `from agent_core import Hooks`。

**健壮性（评审「扩展置于后台，不改 LLM 上下文」）**：`hooks is None` 时三处完全不触发；钩子抛异常被吞掉
（仅记日志不阻断主链路），保证扩展故障不影响业务闭环。

即用组件（**默认不挂载**）：`app/features/assistant/hooks.py:14` `TruncateOversizedToolResultHook`——
`after_tool` 阶段把超 `max_chars` 的 `content`/`text` 截断，防止超大 tool result 撑爆上下文；需要时在
`RuntimeDeps(hooks=TruncateOversizedToolResultHook())` 注入即可。

## Considered Options

1. **改内核在每个 subagent 内联干预逻辑** —— 拒绝。散落、不可组合、易与业务耦合，违背分层。
2. **仅依赖 manifest SOP 注入（现状）** —— 不足。SOP 是 LLM 可见提示词，无法做「不可见」的裁剪/审计。
3. **agent_core 增加可选 Hooks seam（采用）** —— 与参考架构同构；LLM 不可见、可组合、默认零行为、向后兼容。

## Consequences

- 正向：业务可注入审计/裁剪/约束而不碰内核；`AgentRuntime` 接受 `hooks` 且默认无行为（评审 §7 P2 判据满足）。
- 约束：钩子实现须**幂等、轻量**——避免在其中发起额外 LLM 调用或阻塞主链路；重写消息须保持
  `role`/`tool_calls`/`ref` 成对不变量（ADR-0033），否则破坏 provider 的 ToolRequest↔ToolResponse 配对。
- 取舍：仅 query（声明 tools 走 tool loop 的 subagent）会触发三个固定点；纯文本/单调用 subagent（tutor/question）
  不跑 tool loop，无挂载点（符合 ADR-0033 opt-in 原则）。
