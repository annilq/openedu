# 08 · 多模型接入（Ollama / 自定义）+ 流式响应（Genkit 编排）+ 轻量 GenUI

> 标签：`wayfinder:ticket`
> 来源：`/grill-with-docs` 收敛（2026-08-31）；**v1 决策于 08-31 经用户复核由「LangChainProvider 扩展」改为「Genkit Python 编排流式 flow」**
> 决策基线：**ADR-0015**（决策 3 已改为 Genkit 编排；ADR-003 框架 import 隔离延续）

## What to build
在不降级儿童内容安全（ADR-008）的前提下：①新增 `app/ai/` Genkit 流式编排层（`tutor_ask` 与 `generate_questions` flow，内置 SSE + `chunk_type` 字段级结构化流式），按 `ModelConfig` + settings 解析 Ollama / OpenAI-compat / 内置模型；②新增 `ModelConfig` 表与 `GET /models` + 家长 CRUD，模型选择器仅家长可用；③为 `/tutor/ask` 与 `/tasks/generate` 增加 SSE 流式变体，前端边收边渲染（答疑打字机、出题逐张题卡）；④流式输出仍由后端独占做 `check_input`/`check_output`，儿童端绝不闪现违规片段。**非流式**真实调用仍走既有 `LangChainProvider`（ADR-003 框架隔离：`langchain` 仅在 `LangChainProvider`、`genkit` 仅在 `app/ai/`）。

## 关键决策（详见 ADR-0015）
- **后端统一代理**：Flutter 只连 `/api/v1` SSE，模型由后端调，安全层永不绕过。
- **轻量流式渲染**：SSE 推 `token` + 结构化事件，不引入 `genui` catalog 真·GenUI。
- **改用 Genkit Python 编排流式 flow**：`app/ai/` 为唯一 `import genkit` 边界；`serve_flow` 挂 FastAPI 路由、原生 SSE、`chunk_type` 字段级流式、工具调用（T11 检索作接地工具）。
- **模型注册 = 配置驱动 + 家长自定义**：`GET /models` + `ModelConfig` 表（仿 `TutorQuota`）。
- **选择器仅家长**：娃娃继承默认模型，娃娃端无下拉。
- **流式安全 = 缓冲 + 整体 `check_output` 后放行**（v1 接受首字延迟）。

## 后端任务
- [ ] `app/core/config.py`：新增 `OLLAMA_BASE_URL`（默认 `http://localhost:11434`）、`DEFAULT_MODEL`、`BUILTIN_MODELS`（env JSON）、`MODEL_FALLBACK`（默认 none）、`MODEL_APIKEY_SECRET`（Fernet 密钥）。
- [ ] `pyproject.toml`：新增 `genkit` / `genkit-fastapi` / `genkit-openai` / `genkit-ollama`（须 `uv add` 实测 Python 3.14 可解析）。
- [ ] `app/ai/__init__.py` + `app/ai/genkit_app.py`：`Genkit` 实例 + 插件注册（ollama / openai）；`resolve_model(model_ref | ModelConfig)` → `ollama/{m}` / `openai/{m}`（`base_url`/`api_key` 经插件配置或 env）；`mock` 模式返回 `None`，由端点回退 `MockProvider`。
- [ ] `app/ai/flows.py`：`tutor_ask_flow`（文本 token 流式，注入 `_SYSTEM` 年龄锁 + 知识库接地工具）+ `generate_questions_flow`（`chunk_type=QuestionModel` 字段级流式，逐题产出）；flow 内调用 `domain/safety` 做 `check_input`（入参）/ `check_output`（缓冲后）。
- [ ] `app/models.py` + `app/core/db.py`：`ModelConfig` 表 + `run_migrations` 幂等建表（`(parent_id, label)` 唯一）。
- [ ] `app/crud.py` + `app/api/routes/models.py`：`GET /api/v1/models`（parent：内置 + 该 parent 自定义）、`POST/PUT/DELETE /api/v1/models`（api_key 写入前 Fernet 加密、越权 403）、`GET/PUT /api/v1/models/default`（家长默认）。
- [ ] `app/api/routes/stream.py`（新）：`POST /api/v1/tutor/ask/stream` 与 `POST /api/v1/tasks/generate/stream`，调用 `app/ai` flow、把 Genkit 分块翻译为本项目 SSE 信封（`token` / `question` / `safety_refusal` / `done` / `error`），`done` 带 `usage.seconds` 供 `add_tutor_usage`；复用 `require_role` + `check_quota` + `check_input`。
- [ ] 失败处理：provider 不可达 → 502 友好文案；`MODEL_FALLBACK=mock` 时才静默回退 Mock。

## 前端任务
- [x] 网络层：新增 SSE 客户端 `shared/data/remote/sse_client.dart`（`SseClient.stream` → `NetworkService.streamPost` 产出 `SseEvent`），解析 `event:/data:` 信封；`NetworkService.streamPost` 已在抽象类 + `DioNetworkService` 实现（Dio 拦截器注入 Token、错误统一转 `AppException`）。
- [x] `models.dart`：`ModelInfo` / `ModelListResp` / `ModelCreateReq` / `ModelUpdateReq` 已存在；SSE 信封在 `sse_client.dart` 以 `SseEvent(event, data)` 统一表示，`askStream` 内联解析 `token`/`reason`/`message`（未单列 TokenEvent 等类，等价覆盖）。
- [x] `features/tutor`：`TutorNotifier.askStream()`（消费 SSE，token 追加进占位 AI 气泡；`safety_refusal`→🛡️ 气泡 `blocked`、`error`→⚠️ 气泡、`done`→落定对话）；`tutor_chat_screen._send` 调用 `askStream` 并逐 token 自动滚底（打字机）。
- [x] `features/home`（`parent_task_form_view`）：`AppModelSelector`（读 `GET /models`，首项「默认（后端自动）」=null）已接入，提交时 `_modelId` 经 `taskGenNotifierProvider.generate(model:)` 透传 `/tasks/batch-generate`（落库，走原有草稿审核流）。新增「预览出题」按钮：调 `taskGenNotifierProvider.preview()` 走 `/stream/tasks/generate` SSE，题卡逐张浮现（`QuestionPreview` 模型 + `TaskGenPreview` state，`_PreviewCard` 渲染）；预览满意后「保存为任务」再落库（复用 `/tasks/batch-generate`）。
- [x] 家长设置：新增「模型管理」页 `parent_model_management_screen.dart` + `model_form_dialog.dart`（列表内置 + 自定义、增/改/删、设默认、填 `base_url/model/api_key`；`api_key` 前端不回显、后端 Fernet 加密）；`home_screen` 家长导航 `7 => ParentModelManagementScreen`（标签「模型管理」）。娃娃端无下拉（继承默认模型，符合决策）。
- [x] 安全：`check_output` 未过 → 后端发 `safety_refusal`，前端气泡显示 `🛡️ …` 且原文不渲染；复用 `AppException` 处理非 2xx。

## 测试
- [x] 后端：`tests/ai/test_model_resolution.py`、`tests/api/routes/test_models.py`、`tests/api/routes/test_tutor_stream.py`、`tests/api/routes/test_generate_stream.py` 均已落地（前序会话 6 个失败已全修，`uv run pytest` 119 passed / 1 skipped、`ruff` 零警告）；新增 `tests/api/routes/test_generate_stream_smoke.py`（gated by `RUN_LLM_SMOKE`，需 `BUILTIN_MODELS` 含 `provider=ollama` 的模型）。
- [x] 前端：新增 `test/sse_client_test.dart`（SSE 信封解析：多事件按空行切分 / CRLF 归一化 / 无尾空行仍解析）+ `test/tutor_notifier_ask_stream_test.dart`（`askStream` 状态机：token 累积→`TutorLoaded`、safety_refusal→🛡️ `blocked` 气泡、error→⚠️ 气泡）；`flutter test` 全绿 39 passed。
- [x] 门禁：`uv run pytest` 全绿（119 passed / 2 skipped）、`ruff` 零警告；`flutter analyze` 0 问题；`flutter test` 全绿（39 passed）。

## 风险 / 待决
- 🔴 **api_key 加密**：`ModelConfig.api_key` 必须 Fernet 加密存储，密钥取 settings，严禁明文落库。
- 🟠 **Genkit × Python 3.14**：`requires-python>=3.10` 名义兼容，但须 `uv add` 实测传递依赖在 3.14 可解析；若不通过，回退「LangChainProvider 扩展（原决策 3）」或降 Python（不推荐）。
- 🟠 **首字延迟**：v1 答疑缓冲整体校验，本地 Ollama 通常可接受；体感差则后续叠 chunk 级软过滤（ADR-0015 已留扩展点）。
- 🟠 **真·GenUI**：未采用 `genui` catalog；若后续要 CopilotKit 式交互（模型发 UI 指令）需另立票，并解决 WebSocket/A2UI 与 SSE 协议对齐。
- 🟡 **ADR-012 版权**：自定义模型不改变内容源约束，知识库仍为自编内容（AC-305 检索能力已落地，授权未解）。
