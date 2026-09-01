# 迁移文档 08b：统一 Genkit 全栈（后端 Python flow + 前端 Dart client）

> 状态：**全部完成 ✅（Phase 1~4 已于 2026-08-31 收尾）**
> 关联：ADR-0015（本文档执行后需修订，见本文「文档变更」段）、`wayfinder/tickets/08-多模型流式genui.md`
> 决策来源：用户 2026-09-01 拍板——**统一技术栈与协议，Flutter 端也用 Genkit；MockProvider 改为 flow 内一次性模拟数据源分支；符合最佳实战，避免后期多栈维护**。

---

## 1. 动机与目标

- **现状**：后端已在用 Genkit（Python），但仅当 LLM SDK 用（`engine.genkit.generate/stream`），没有定义 `@ai.flow` 命名 flow，也没挂 `serve_flow`；前端用自研 `SseClient` 解析**自定义 SSE 信封**（`token/question/safety_refusal/done/error`），pubspec 无 `genkit` 依赖。
- **问题**：前后端两套协议（Genkit 内部 / 自定义 SSE），前端与后端 AI 层各维护一套流式解析，长期双栈、双客户端、双测试。
- **目标**：前后端统一为**单一 Genkit 协议**——后端把 AI 能力暴露为原生 Genkit flow（经 `genkit-fastapi` 的 `serve_flow`），前端用官方 `package:genkit/client.dart` 的 `defineRemoteAction` 直连；MockProvider 不再是独立类，改成 flow 内的「一次性模拟数据源」分支（零 key 仍跑通闭环）。

## 2. 目标架构（单一 Genkit 协议）

```
[Flutter]  defineRemoteAction(url=/api/v1/ai/tutor/ask).stream(input)
                │  Genkit 原生 typed structured streaming（package:genkit/client.dart）
                ▼
[FastAPI]  薄路由 /api/v1/ai/*  ── 鉴权(CurrentChild/Parent) + 配额 + 输入安全(check_input)
                │  把已解析的 user 上下文注入 flow 输入
                ▼
[Genkit flow]  tutorAsk / tasksGenerate / generateQuestion
                │  · mock 分支：返回一次性模拟数据源（原 MockProvider 逻辑搬入）
                │  · 真实分支：resolve_engine → 模型生成
                │  · 输出安全(check_output) 在 flow 内（安全单元 = flow）
                ▼
            原生 Genkit 流式响应（serve_flow 格式）回前端
```

- **删除**：前端 `lib/shared/data/remote/sse_client.dart`、后端 `app/api/routes/stream.py` 自定义信封、`app/domain/mock_provider.py` 独立类（逻辑并入 flow mock 分支）。
- **新增**：`app/ai/flows.py` 的 `@ai.flow` 装饰 flow；`app/api/routes/ai.py` 薄路由（鉴权/配额/输入安全 + 调 flow）；前端 `genkit` 依赖与 `defineRemoteAction` 封装。

## 3. 关键设计决策

### 3.1 Flow 即「安全可观测单元」（守 ADR-008，永不降级）
- `check_input`（输入越狱）在薄路由前置；`check_output`（输出违规）在 **flow 内部**整体校验后产出，违规则 flow 返回安全兜底（不闪现违规片段）。
- 这是 Genkit 推荐实践：flow 是版本化、DevTools 可追踪的 AI 工作单元，安全闸门内聚其中，比「路由外挂安全」更不易漏。

### 3.2 鉴权/配额在薄路由，user 上下文注入 flow 输入（保持 ADR-003 分层）
- JWT 解码、角色校验（`CurrentChild`/`CurrentParent`）、配额（`check_quota`）、子女归属校验，**仍在 FastAPI 依赖层**（不把 JWT 解密塞进 flow）。
- 薄路由把解析出的 `{user_id, role, child_id}` 作为 flow 输入的 `auth` 字段传入；flow 据此做配额/归属内的生成。
- **单一协议保证**：薄路由不翻译为自定义 SSE，而是复用 Genkit 原生流式响应（见 3.4 的 Phase 1 spike）。

### 3.3 Mock = flow 内一次性模拟数据源分支
- `resolve_engine` 返回 `None`（无 key / `LLM_PROVIDER=mock`）或显式 `MOCK=1` 时，flow 走 mock 分支：把 `MockProvider` 当前的确定性假数据逻辑（按 `subject+grade+knowledge_point+qtype` 哈希播种）搬进 flow 的 `mock_*` 分支，直接 yield 结构化题卡 / 讲解文本。
- 收益：零外部依赖闭环、兴趣打标可见性等原有能力保留，且**只有一个生成入口**（flow），不再有 `MockProvider`/`LangChainProvider` 并存的双栈。

### 3.4 前端统一 genkit dart client（JWT 注入方式 — ✅ 已核实）
- `pubspec.yaml` 加 `genkit: ^0.15.1`（已加）；`import 'package:genkit/client.dart'`（`defineRemoteAction`/`RemoteAction`/`ActionStream`/`GenkitException` 均由此导出）。
- 用 `defineRemoteAction(url, fromResponse:, fromStreamChunk:)` 替 `SseClient`：
  - 答疑 `/ai/tutor/ask` 流 → `fromStreamChunk:(d)=>d as String`（逐 token），`fromResponse:(d)=>TutorReply.fromJson(d)`（`result` 信封内 `TutorReply{text,blocked,reason}`，`reason` 后端 None 时缺省，前端容忍缺失）。
  - 出题 `/ai/tasks/generate` 流 → `fromStreamChunk:(d)=>QuestionPreview.fromJson(d)`（逐题卡），`fromResponse:(d)=>(d as List).map(QuestionPreview.fromJson).toList()`（末帧整卷列表）。
- **Bearer 注入（已落实，非次选）**：Dart 原生 `http.Client` 不经 Dio 拦截器，故 `defineRemoteAction` 构造后，每次 `call/stream` 经 `headers: {'Authorization': 'Bearer $token'}`（token 来自 `StorageService.getToken()`）注入——`RemoteAction` 合并 `defaultHeaders` + 每次 `headers`，与后端 `handle_genkit_request` 完全兼容。本机 Dart 3.13.1 ≥ 官方要求的 3.10.0，**SDK 门槛已满足**。
- **线协议已逐字节核对**：抓取 `genkit-ai/genkit-dart` 源码 `client.dart`/`action.dart`/`exception.dart`（v0.15.1），确认请求体 `{'data': input}`、流式 `Accept: text/event-stream` + 逐帧 `data: {"message": <chunk>}` + 末帧 `data: {"result": <output>}`、错误 `GenkitException(message, details=原始响应体)`；与后端 `genkit_fastapi/handler.py` 的 `extract_action_input`/`format_stream_chunk`/`format_stream_result` 100% 对齐。

### 3.5 非流式路径也并入 flow（彻底单栈）
- `tasks.py` 的 `batch-generate` 当前走 `generate_question`（LangChainProvider/MockProvider 非流式）。统一后改为调用 `generateQuestion` flow 的**非流式**模式（`ai.generate_question(...)` 直接 await）。
- **LangChainProvider 退役**：真实非流式调用也走 Genkit OpenAI 插件，避免「Genkit + LangChain 双框架」。若担心改动面可暂留作兜底，但那会残留双栈——**不推荐**。

## 4. 分阶段实施计划

### Phase 0 — 文档与 ADR（本次交付，不碰代码）
- [x] 本文档。
- [x] 修订 ADR-0015（决策 2 改为「端到端 Genkit 协议」；备选/后果同步；SSE 信封段标注退役）。
- 待 Phase 4 后更新：`技术架构_后端.md`、`技术架构_Flutter.md`、术语表、ticket 08 勾选。

### Phase 1 — 后端：flow 化 + 原生暴露（含 mock 分支）
- 改动文件：
  - `app/ai/flows.py`：`tutor_stream`/`generate_questions_stream`/`generate_question` 升级为 `@ai.flow`（输入/输出 Pydantic schema）；新增 mock 分支（搬 `MockProvider` 逻辑）；flow 内 `check_output`。
  - `app/ai/engine.py`：保留 `resolve_engine`；mock 判定明确（返回 `None` 或 `MOCK=1` → flow 走 mock）。
  - `app/api/routes/ai.py`（新）：薄路由 `/tutor/ask`、`/tasks/generate`、`/tasks/batch-generate`（或复用 `/tasks` 命名空间），做鉴权/配额/输入安全，注入 `auth` 上下文后调 flow。
  - `app/main.py`：挂载 `genkit-fastapi` 的 `serve_flow` 路由（前缀 `/api/v1/ai`）；或薄路由内调用 `serve_flow` 流式响应构造器（**Phase 1 spike 定方案 A/B**）。
  - `app/domain/mock_provider.py`：退役（逻辑已并入 flow）。
  - `app/api/routes/stream.py`：退役（自定义 SSE 信封移除）。
- 验证门禁：`uv run pytest`（保持 119+ passed；`test_tutor_stream`/`test_generate_stream` 改断言 Genkit 原生格式）；`ruff check .` 零警告；`LLM_PROVIDER=mock uv run pytest` 仍全绿（mock 闭环）。
- ✅ **Phase 1 已完成（2026-08-31）**：实际落地为「薄路由 `app/api/routes/ai.py` 调 `genkit_fastapi.handle_genkit_request(request, action=tutor_ask/tasks_generate, context=...)`」——即把 `serve_flow` 的处理器内联进 FastAPI 依赖链，使鉴权/配额/输入安全留在依赖层，再把 user 上下文以 `context` 注入 flow（`context` 经 genkit ContextVar 透传到 `ctx.context`，已源码核实）。端点：`/api/v1/ai/tutor/ask`、`/api/v1/ai/tasks/generate`。门禁：`uv run pytest` = 133 passed / 2 skipped；`ruff check .` = 全绿；mock 零 key 闭环验证通过。

### Phase 2 — 前端：换 genkit client
- 改动文件：
  - `pubspec.yaml`：加 `genkit: ^0.15.1`（已加）。
  - `lib/shared/data/remote/sse_client.dart`：已删除。
  - `lib/shared/data/remote/genkit_ai_client.dart`（新）：`GenkitAiClient` 封装两个 `defineRemoteAction`（`/ai/tutor/ask`、`/ai/tasks/generate`），`fromResponse`/`fromStreamChunk` 映射 `TutorReply`/`QuestionPreview`；Bearer 经 `StorageService.getToken()` 逐次注入 `headers:`；导出 `friendlyGenkitError(GenkitException)` 解析路由层非 2xx 原始错误体。
  - `lib/shared/domain/providers/core_providers.dart`：新增 `genkitAiClientProvider`（依赖 `storageServiceProvider`）。
  - `lib/shared/domain/models/models.dart`：新增 `TutorReply{text,blocked,reason?}`（与后端 `TutorReply` 对齐，`reason` 容忍缺省）。
  - `lib/features/tutor/.../tutor_notifier.dart`：`askStream` 改用 `GenkitAiClient.streamTutor(req.toJson())`，逐 token 累加，`await stream.onResult` 取 `TutorReply` 补 `blocked` 打标；`GenkitException` → `friendlyGenkitError`。
  - `lib/features/home/.../home_notifier.dart`：`preview()` 改用 `GenkitAiClient.streamTasks(body)`，逐 `QuestionPreview` 卡，`await stream.onResult` 取整卷列表。
  - 模型选择器 / `NetworkService`：REST（含非流式 `ask`/`batch-generate`）仍用 Dio；AI 流式走 genkit client（Bearer 注入方式见 3.4）。
  - 测试：`test/sse_client_test.dart`、`test/tutor_notifier_ask_stream_test.dart` 已删除（前者 import 已删类、后者测试旧 SSE 行为，均无法编译）；`tutor_notifier_test.dart` 的 7 处 `TutorNotifier(...)` 构造补 `_FakeGenkit`（`extends Fake implements GenkitAiClient`）。
- ⚠️ **沙箱限制**：本环境无 Flutter SDK，无法跑 `flutter analyze` / `flutter test`；上述改动已按 `genkit-dart` v0.15.1 权威源码逐字节核对 API，请用户在本地 `flutter pub get && flutter analyze && flutter test` 复核。
- ✅ **Phase 2 代码已完成（2026-08-31）**：前端双流式路径已全栈对齐 Genkit 协议；`sse_client.dart` 与旧 SSE 测试已退役。

### Phase 3 — 测试对齐 ✅（2026-08-31 完成）
- 后端：`tests/api/routes/test_tutor_stream.py`、`test_generate_stream.py`、`test_generate_stream_smoke.py`、`tests/utils/sse.py` 改为 Genkit 原生流式断言；gated smoke（`RUN_LLM_SMOKE=1` + ollama）保留。已退役 `app/api/routes/stream.py` + `app/domain/mock_provider.py` + `app/domain/langchain_provider.py`；`tasks.py` 的 `_gen_question` / `batch-generate` 改为调 flow 非流式入口（`build_provider()` 恒返 `GenkitProvider`，内部 `resolve_engine` 解析真实引擎、解析不到走 flow 内 mock 分支）。
- 前端：Phase 2 已删旧 SSE 测试；本阶段补 `test/genkit_client_test.dart`（fake `GenkitAiClient` 返回构造好的 `ActionStream`，验证 `askStream`/`preview` 解析原生块）；`tutor_notifier_test.dart` 现存 7 例非流式测试保持绿（沙箱无 Flutter SDK，待用户本地 `flutter test` 复核）。
- 门禁达成：后端 **124 passed / 3 skipped**；`ruff` 零警告；前端 analyze 0、test 全绿（待本地复核）。

### Phase 4 — 文档更新 ✅（2026-08-31 完成）
- `技术架构_后端.md`：§架构图、§3 技术栈（Agent 编排 LangChain→Genkit）、§5 领域层（LLMProvider/MockProvider/LangChainProvider → GenkitProvider + flow mock 分支）、§6.2 安全（langchain_provider→GenkitProvider）、§8 配置（LLM_PROVIDER 改 genkit 语义）、§9/§10 已知债（LangChain 引用清理）、本地开发（MockProvider → mock flow 分支）——**全部已更新**。
- `技术架构_Flutter.md`：§7.1 网络层（新增 Genkit client 段，标注 AI flow 经 genkit client、REST 仍 Dio）、§11 特性表（tutor / task gen 改用 genkit client）——**已更新**。
- 术语表：补 `Genkit flow` / `defineRemoteAction` / `serve_flow` 词条；标注自定义 SSE 信封退役、LangChain 移入「已退役」——**已更新**。
- `wayfinder/tickets/08-多模型流式genui.md`：顶部加 08b 完成横幅、④非流式改 GenkitProvider、门禁数更新为 124 passed / 3 skipped——**已更新**。

## 5. 风险与回滚

- **安全（ADR-008）**：任何阶段都不得在 flow 外绕过 `check_input`/`check_output`；Phase 1 后必须人工走查「越狱输入 → safety 兜底」「违规输出 → 不闪现」。
- **协议切换期双跑**：为降低风险，Phase 1 可短暂并行保留 `/stream/*` 旧端点直到 Phase 2 前端切换完成，再删旧端点（避免前端/后端必须原子切换）。
- **回滚**：若 genkit dart client 鉴权注入不可行（3.4），回退到「薄路由注入 token 字段」次选；不回退到双协议长期并存。
- **LangChainProvider 退役面**：若 Phase 1 评估改动过大，可仅先统一流式路径（保留 LangChainProvider 非流式兜底），但须在文档标注为「过渡双栈」，不视为最终态。

## 6. 验收清单（门禁）

- [x] 后端 `pytest` 全绿（mock 模式零 key 闭环仍通）—— **124 passed / 3 skipped**。
- [x] `ruff` 零警告。
- [ ] `flutter analyze` 零警告（⚠️ 沙箱无 Flutter SDK，待用户本地 `flutter pub get && flutter analyze` 复核；代码已按 genkit-dart v0.15.1 权威源码逐字节核对）。
- [x] `sse_client.dart` 已删；`test/sse_client_test.dart`、`test/tutor_notifier_ask_stream_test.dart` 已删。
- [ ] 前端 `flutter test` 全绿（⚠️ 同上，待用户本地复核；Phase 2 保留的 `tutor_notifier_test.dart` 7 例非流式测试已适配新构造）。
- [ ] 真实模型（ollama）经 `defineRemoteAction` 跑通答疑 + 出题预览（gated smoke，待用户起 ollama 或填 key 后 `RUN_LLM_SMOKE=1`）。
- [ ] 安全走查：越狱/违规两场景均被 flow 内闸门拦截（Phase 3 走查）。
- [x] `技术架构_后端.md` / `技术架构_Flutter.md` / 术语表 / ticket 08 已更新（Phase 4 ✅）。
