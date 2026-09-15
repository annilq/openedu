# 模型管理：家长自定义模型统一经 ModelConfig（Fernet 加密）

> **部分被取代（ADR-0039）**：本文中的「内置模型由管理员 `BUILTIN_MODELS` 提供」已废止——内置模型目录被整体移除，所有模型一律由家长在「模型管理」中手动添加（新增必填 api_key）。`ModelConfig` 表 + Fernet 加密 + `is_default` 标记 + `resolve_engine` 单一解析入口这些**核心决策不变**；下文相关句子中的 `BUILTIN_MODELS` 请按此理解。

家长自定义模型统一收口到 `ModelConfig` 表，替代原先散落各处的本地 `LLM_PROVIDER` / `DEEPSEEK_*` 环境变量；api_key 落库前经 Fernet 加密，仅家长可读写，~~内置模型由管理员 `BUILTIN_MODELS` 提供~~（已被 ADR-0039 废止），引擎解析统一走「模型引用」。

- **Repository 分层**：model_management 的业务数据访问收口在 repository 层（`backend/app/features/model_management/repository.py:1`）；写库时 `api_key_enc=encrypt(api_key)` 加密存储（`:7`、`:49`）。
- **家长自定义模型表**：`ModelConfig` 仅家长可增删改，`api_key` 字段 `api_key_enc` 经 Fernet 加密（`backend/app/db/models/model_config.py:7`、`:19`）；`is_default` 标志标记家长默认模型（`:20`）。
- **仅家长可用的路由**：模型管理 REST 仅 `CurrentParent` 可访问，provider 仅放行 `ollama` / `openai_compat`（`backend/app/features/model_management/router.py:1`、`:23`、`:48`、`:81`）。
- **api_key 加密实现**：`crypto.encrypt` / `crypto.decrypt` 以 `MODEL_APIKEY_SECRET`（缺省回退 `SECRET_KEY`）派生 Fernet 密钥（`backend/app/core/crypto.py:1`、`:26`、`:35`）。
- **引擎解析取代 env**：`engine.resolve_engine` 把「模型引用」解析为引擎+model，优先级统一走 ModelConfig ~~/ `BUILTIN_MODELS`~~（内置目录已由 ADR-0039 移除），不再读取本地 `LLM_PROVIDER`（`backend/app/ai/engine.py:1`、`:8`、`:106`）；`is_default` 回落在 `:140-145` 与 `repository.get_default_model_config`（`:91`）。
- **AI 编排层收口**：`app/ai` 作为跨 feature 的 AI runtime 承载 engine 解析（`backend/app/ai/__init__.py:1`、`:3`），观测落库已另归 assistant（ADR-0026）。
- **测试守护**：接口 CRUD/加密/越权（`backend/tests/api/routes/test_models.py:1`）与解析优先级（`backend/tests/ai/test_model_resolution.py:1`）共同守护此决策。

**Considered Options**：① 沿用本地 `LLM_PROVIDER` + 各 feature 各自读 env（分散、密钥明文，拒绝）；② 全部模型经 `ModelConfig` 表 + Fernet 加密 + `is_default` 标记（采用）。

**Consequences**：模型配置家长自助、密钥不落明文；引擎解析单一事实源，新增 provider 只需在 repository/router/engine 三处加分支；`resolve_engine` 在无配置时返回 None（无离线 mock 兜底）。
