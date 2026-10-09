# ADR-0080 知识点聚焦注入会话系统提示（knowledge_point_id → ctx.extra）

- 状态：提案（待评审）
- 日期：2026-10-10
- 关联：ADR-0072（推荐操作 + 知识点作用域入口；§2「会话系统提示围绕知识点聚焦」）、ADR-0033（query 工具与 `requires_tool_data`）、ADR-0067（课件上下文透传）、ADR-0061 §U（交互讲解读路径单一入口）

## 1. 背景（Context）

ADR-0072 §2 承诺「会话系统提示围绕知识点聚焦」，但**至今未落地**。读码核实（非凭记忆）：

- `ctx.extra["knowledge_point_id"]` 已在 `service.py:579` 随每轮请求下发，但 **`tutor` / `query` 两个 subagent 都不读它**——`tutor/agent.py:97` 的 `knowledge_point` 只从 `courseware` 取 → **无课件上下文的普通伴学里「所属知识点：」恒为空串**。
- `_resolve_kp_context`（`service.py:155`）**已存在**，且已含 `core.guard.require_owned` 归属校验，返回精确 `(subject, grade, semester, name)`；但它**当前只被 quiz 路径与推荐操作目录消费**。
- 前端**无需改动**：`assistant_chat_page.dart:105-107` 注释确认「把课件上下文随每条消息带下去，后端每次按 `courseware` 重新解析」，`knowledgePointId` 已在每轮请求体里。

## 2. 决策（Decision）

### 2.1 解析归属：服务端单一入口复用 `_resolve_kp_context`

- `chat` 构造 `ctx` 前调 `_resolve_kp_context`（内部走 `require_owned`）；命中则写 `extra["knowledge_point"] = {"subject","grade","semester","name"}`（**结构化**，由 subagent 各自渲染，避免各处重复拼串）；未命中**不写该键**。
- 越权 / 查不到 → 沿用既有回落（courseware 的 name 口径 → None），与现状一致，无新越权面。

### 2.2 注入段：subagent 各自拼，**不改安全锁**

- `tutor.initial_system` 与 `query.initial_system` 在既有分段之后追加一段：
  ```
  【知识点聚焦】本会话聚焦：「{name}」（{subject} · {grade}年级 · {semester}）。
  回答请围绕该知识点展开；若用户明显偏向其它知识点，先简要回答再询问是否切换焦点。
  ```
- `query` 版本另加一句「查询仍须依托工具数据」，以**维持 `requires_tool_data=True` 契约不变**。
- ⚠️ **不修改 `tutor_system_prompt`**（`domain/safety.py`）——它是按 `grade/subject` 生成的安全锁，业务焦点必须物理分离。

### 2.3 quiz 路径沿用已有精确口径

- `_quiz_generate_stream` 继续用 `_resolve_kp_context` 的结果出题，不重复解析、不改口径。

## 3. 后果（Consequences）

- 从课件页进入的助手，其**会话系统提示**真正带上焦点知识点（学科 · 年级 · 学期 · 名称），兑现 ADR-0072 §2。
- 无课件上下文的普通伴学行为**完全不变**（不写键 → 无注入段）。
- 后端可单测：有 / 无课件上下文、越权 id、安全锁 diff 为空。
- 用户放行后实现，落到 ticket `.scratch/ai-prompts-hardening/issues/02-*.md`。

## 4. 备选（Considered Options）

- **让普通伴学也自动带学员当前进度 / 薄弱知识点**：否决（本轮）。需按学员从库解析取数、涉及归属与「是否越权暴露」，风险高，留后续单独议。
- **把聚焦写进 `tutor_system_prompt`**：否决。安全锁不该混业务焦点；且它按 `(grade, subject)` 生成，注入点不在同一上下文。
