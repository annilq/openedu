# MEMORY.md — 长期记忆（已收敛）

## 启动约定
- 每会话第一步 Read 根 `AGENTS.md`（`/Users/yunqi/Documents/develop/openedu/AGENTS.md`），含包管理器（后端 uv / 前端 flutter）、每任务命令、硬约束、细分规范链接、macOS 联调网络权限。

## 项目位置
- 娃娃学习App：`/Users/yunqi/Documents/develop/openedu`（原 WorkBuddy 目录已弃）。

## 后端（FastAPI + SQLModel + uv）
- 验证：`cd backend && uv sync` / `uv run pytest`。无 Alembic；迁移手写于 `app/core/db.py:run_migrations`（兼容 sqlite TEXT / postgres JSON，幂等）。
- **Feature-First 架构（ADR-0027，2026-09-08 落地）**：每能力一个 `app/features/<name>/`（router+schemas+repository+service）；ORM 表集中 `app/db/models/`；共享内核 `app/domain/`（provider/safety/retriever/quota 等 AI 基础设施）+ `app/core/`（config/security/errors/db/deps），不拆；`app/ai`（Genkit flow）+ `app/ai/subagents`（ADR-0021/0024 编排）留共享内核。~**已删** `app/crud.py`/`app/api/routes/`；~`app/models.py` **保留为 re-export shim**（仅 `from app.db.models import ...` 兼容 13+ 处旧 `from app.models import X`，ORM 实体以 `app/db/models/` 为唯一注册源）；`app/api/deps.py` **保留**（`CallerDep`/各角色依赖）。依赖统一走 `app.core.deps`（CurrentUser/CurrentParent/CurrentChild/CallerDep/SessionDep）。`TutorLog` 落库只由 `app/features/assistant/router.py` 负责（带真实 grade），SubAgent/flow 不重复落。
- **AI 助手统一入口（ADR-0024/0025/0026，2026-09-08 落地）**：所有 AI 功能（出题/伴学答疑/查任务/治理观测除外）统一走 `POST /api/v1/assistant/chat`（SSE，AG-UI 事件信封）。旧 `/ai/tutor/ask`、`/ai/tasks/generate`、`/tutor/ask` 已删除；`/tutor/{logs,quota,usage}` 与 `/ai/debug/conversations*` 属治理/观测，保留。运行时 `app/ai/runtime/`（protocol/intent_router/manifest/runtime）+ `app/ai/subagents/<business>/` 文件夹化 subagent（question/tutor/tasks，各含 manifest.py+agent.py+tools/+skills/）；意图路由 = manifest `triggers` 规则优先 + 启发式兜底。前端 `lib/features/assistant/`（SSE client + notifier + 悬浮按钮 + 对话弹窗）统一消费；首页出题（home_notifier）与伴学（tutor_notifier）均已改接 `/assistant/chat`。**genkit 已彻底退役**：前端 `genkit_ai_client.dart` 与 `pubspec.yaml` 的 `genkit` 依赖均于 2026-09-08 删除（`flutter pub get` 已清其传递依赖）；后端 `app/ai/flows.py` 的孤儿 genkit flow（tutor_ask/tasks_generate）已删，`genkit` 仅作底层 LLM 引擎经 `engine.genkit` 被 `app/domain` 调用，不经 `genkit_fastapi` 暴露原生 action。
- LLM：`resolve_engine` 解析优先级 = 家长 `ModelConfig` 表 → `BUILTIN_MODELS`(env) → 全局 `LLM_PROVIDER` → None(走 flow 内 mock)；业务只依赖 `LLMProvider` 抽象。`genkit` 仅 import 于 `app/ai/`。Genkit 不做编排层（见评估注记）。
- **测试一律不得依赖真实模型（2026-09-10 定规，CI 红线后立）**：`tests/conftest.py` 在 import app 前置 `os.environ["LLM_PROVIDER"]="mock"`，并 autouse 打桩 `app.ai.runtime.runtime.build_provider` 为 `tests/utils/fake_provider.FakeLLMProvider`（确定性文本/题卡）。根因：本地 `backend/.env` 有 deepseek key → 本地绿、CI 无 key → 出题/答疑断言红（本次 2 failed）。**新增任何走 LLM 的测试都不许接真模型**（真模型连通性只由 `tests/domain/test_llm_smoke.py -m smoke` 负责）。打桩点必须是 `app.ai.runtime.runtime.build_provider`（该模块 import 期已把名字绑进自身命名空间，改 `app.domain.build_provider` 无效）。副作用：全套件 22s → 6.5s。
- `uv` **不在默认 PATH**：用 `/opt/homebrew/bin/uv`（或 `~/.local/bin/uv`）。
- `TutorService.aexplain` 是唯一实现，`explain` 只是 `asyncio.run(aexplain(...))` 的同步桥（曾因复制粘贴双份导致无引擎时异步侧漏判 `raw is None` → 下发 `answer=None/blocked=False`）。

## 前端（Flutter + Riverpod + shadcn_ui + cupertino_ui）
- 验证：`cd frontend && flutter pub get` / `flutter analyze`（零警告）/ `flutter test`。
- **Flutter SDK 不在默认 PATH**：用绝对路径 `/Users/yunqi/Documents/flutter/bin/flutter`。`flutter test` 必须剥代理：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy /Users/yunqi/Documents/flutter/bin/flutter test`（否则 flutter_tester WebSocket 被本机代理拦截，全部测试加载失败，与代码无关）。
- **shadcn_ui 硬约束（入口是 `ShadApp`=WidgetsApp，整树无 Material 祖先）**：
  - 禁止 Material Chip 家族（`ChoiceChip`等）→ 用 `ShadButton`/`ShadButton.outline` 或 `shared/widgets/app_chip.dart` 的 `AppChip`。`Switch/Checkbox/Radio/Slider` 同理改 shadcn 件（`ShadSwitch` 等）。
  - `AppCard(onTap:)` 用 `GestureDetector` 包裹，禁止 `ShadButton.ghost(width:double.infinity)`（无限宽撑爆卡片内容）。
  - **shadcn `ShadInput` 文字垂直居中根因+修法（2026-09-08，已实测验证）**：shadcn 的 `EditableText` **不暴露 `textAlignVertical`**（全 0.56.3 源码无此参数），默认 `top` → 文字落在编辑盒**顶端**；盒子居中 ≠ 文字居中（compact 偏上 ~2.8px、child 模式偏上 ~8.7px）。`editableTextSize: Size(maxW, controlH-4)` 只钉盒高、**字形仍顶对齐**，不能解决。正确修法：单行输入加 `strutStyle: AppControl.inputStrut(context, style)`（`forceStrutHeight:true` + `height=(controlH-4)/fontSize` 把行高强制撑满编辑盒，Flutter 半行距使字形上下均分→居中）。多行输入（本就该顶对齐）/ 带大竖向 padding 的输入框（如聊天栏，盒子高、文字盒短而自然居中）**勿设** strut。裸 `ShadInput` 也走同款 `inputStrut`。全局约束 `minHeight(controlH)`（AppTextField 另用 `tightFor`），tight 32 盒子含边框+shadcn 内部预留使可编辑区 = controlH-4。
  - 含 `ShadButton` 的 widget 测试需 `ShadTheme` 祖先（`ShadApp.custom(appBuilder: (c)=>MaterialApp(home:X))`）。
  - 描边仅 `outline` 一档；主题映射单向走 `AppTheme.shadThemeData()`；品牌主色统一靛蓝（`AppColors.primary`/`onPrimary`）。
  - `LucideIcons` 来自 `shadcn_ui` 再导出，用到须 import `shadcn_ui`。
- 做题「当场订正」不推进遗忘曲线（2026-09-04）：订正复用 `/tasks/{id}/answer` 就地判分，答对不调 `mark_review_result`。
