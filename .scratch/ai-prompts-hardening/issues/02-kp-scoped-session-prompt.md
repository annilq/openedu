# 02: 知识点聚焦注入会话系统提示（knowledge_point_id → ctx.extra）

**What to build:** 让「从课件页进入的 AI 助手」在**会话系统提示**里真正带上当前焦点知识点（学科 · 年级 · 学期 · 名称），而不只是散落在 quiz 路径与 recommended actions 目录里。做法：在 `chat` 里用已有的 `_resolve_kp_context`（含 `require_owned` 归属校验）把 `knowledge_point_id` 解析成 `(subject, grade, semester, name)`，写进 `ctx.extra["knowledge_point"]`；由 `tutor` 与 `query` 两个 subagent 在 `initial_system` 里拼一段**独立的**【知识点聚焦】段。**不改 `tutor_system_prompt`**（安全锁）。

**Blocked by:** None (can start immediately)

**Status:** done

## 为什么（ADR-0072 §2 未落地）
- `ctx.extra["knowledge_point_id"]` 已在 `service.py:579` 下发，但 **tutor / query 两个 subagent 都不读它**（`tutor/agent.py:97` 的 `knowledge_point` 只从 `courseware` 取）→ 无课件上下文的普通伴学里「所属知识点：」**恒为空串**。
- `_resolve_kp_context`（`service.py:155`）已存在且已含 `require_owned` 归属校验（返回精确 tuple），**当前只被 quiz 路径与 suggested-actions 目录用**。
- 前端**无需改动**：`assistant_chat_page.dart:105-107` 注释确认「把课件上下文随每条消息带下去，后端每次按 `courseware` 重新解析」，`knowledgePointId` 已在每轮请求里。

## 设计
1. **解析与注入（服务端单一入口）**：`chat` 里在构造 `ctx` 前调 `_resolve_kp_context`；命中则 `extra["knowledge_point"] = {"subject","grade","semester","name"}`（结构化，便于两个 subagent 各自渲染，避免各自再拼字符串）。未命中则不写该键（subagent 无段可拼，行为不变）。
2. **注入段（两个 subagent 各自拼，不改安全锁）**：`tutor.initial_system` / `query.initial_system` 里追加一段：
   ```
   【知识点聚焦】本会话聚焦：「{name}」（{subject} · {grade}年级 · {semester}）。
   回答请围绕该知识点展开；若用户明显偏向其它知识点，先简要回答再询问是否切换焦点。
   ```
   - 与 `tutor_system_prompt`（年龄锁，按 grade/subject）**物理分离**，不混入。
   - `query` 版本另加一句「查询仍须依托工具数据」以维持 `requires_tool_data` 契约不变。
3. **quiz 路径沿用精确口径**：`_quiz_generate_stream` 继续用 `_resolve_kp_context` 的结果出题，不重复解析。
4. **越权/缺失回落**：`_resolve_kp_context` 已做——越权或查不到 → 回落 courseware 的 name 口径，再缺则 None（不注入），与现状一致。

## 验收清单
- [x] 有课件上下文（带 `knowledge_point_id`）时，tutor 与 query 的 system prompt 均含【知识点聚焦】段，且内容 = 该 KP 的 `name/subject/grade/semester`（非空）
- [x] 无课件上下文时，system prompt **不含**【知识点聚焦】段，行为与本轮之前一致（无回归）
- [x] 越权 `knowledge_point_id`（他人 KP）→ 不注入该 KP，回落 courseware name 或 None（无越权数据泄漏）
- [x] `tutor_system_prompt` 本体**未被修改**（diff 为空），仅新增独立注入段
- [x] `query.requires_tool_data=True` 契约不变（注入段不引入新的「不查就答」路径）
- [x] 后端 `pytest tests/ai/` 全绿；新增/更新 `test_tutor_subagent` / `test_query_subagent` 断言注入段
- [x] 分层不变量 9：解析经 `app/features/assistant/kp_focus.py:resolve_kp_focus`（内部走 `core.guard.find_owned`，与 `require_owned` 同族；原 `_resolve_kp_context` 已在 ADR-0091 删除，由本模块替代）

**决策锚点：** ADR-0080；`knowledge_point_id` 精确口径（无同名漂移）；普通伴学**不**自动带学员进度/薄弱点（留后续单独议，涉及取数与越权风险）。

## 代码现状核验（2026-10-13，ADR-0089/0091 后已过期部分订正）
> ⚠️ 本票「为什么」段引用的 `_resolve_kp_context`（`service.py:155`）**已不存在**——ADR-0091/0089 重构将 KP 解析下沉到 question 子代理，原 `_resolve_kp_context` 被删。落地口径须更新：

- `ctx.extra["knowledge_point_id"]` 现仅在 `req.courseware` 非空时取值（`service.py:414-418` 取 `req.courseware.knowledge_point_id`），**传入的 `knowledge_point_id` 参数（router.py:64 / service.py:156 签名）被忽略** → 重构引入的回归，须恢复优先读该参数。
- `tutor/agent.py:84` **已读** `extra.get("knowledge_point_id")`，但仅收进 context dict 字段；聚焦段仍只用 `courseware.get("knowledge_point")` name 口径（line 41/101），**无【知识点聚焦】段、未解析 (subject,grade,semester,name) 四元组**。
- `query/agent.py:64 initial_system` **完全不读** knowledge_point（grep 零命中）→ 对 query 的诉求仍成立。
- 前端 `assistant_chat_page.dart:443-450` 仍把 kp 上下文随每条消息带下、`knowledgePointId` 每轮请求带 → 前端无需改动，但 server 必须恢复读该参数。

### 订正后的落地口径
1. `service.py:414` 改 `ctx.extra["knowledge_point_id"]` 优先用传入参数而非仅 courseware 内取值。
2. 重建**最小** KP 聚焦解析（经 `core.guard.require_owned` 取四元组）；`_resolve_kp_context` 已删，建议落独立模块（如 `assistant/kp_focus.py`）以守 ADR-0058 文件棘轮（service.py 已偏大），不重复 question 子代理逻辑。
3. `tutor/query` 在 `initial_system` 读 `extra["knowledge_point"]`（结构化 dict）拼【知识点聚焦】段；**不改** `tutor_system_prompt`（安全锁）。

- **结论：核心缺口（tutor/query 不聚焦、独立 kp 参数被忽略）仍真实存在**，但实现载体与工单原文不同，须按上述口径落地（验收清单其余项不变）。
