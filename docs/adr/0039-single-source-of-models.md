# ADR-0039：模型来源单点化——移除内置模型目录，新增模型强制 API Key

模型只有**一个来源**：家长在客户端「模型管理」里手动添加的 `ModelConfig` 行。为此移除管理员内置模型目录 `BUILTIN_MODELS`（含 `GET /models` 的 `builtin` 字段、前端「内置模型」分区与 `ModelInfo.isBuiltin`），并在**新增**模型时强制 `api_key` 非空（空 / 纯空白 → 422）。编辑仍允许留空 = 不修改密钥。

## 背景：为什么要砍掉第二份声明源

`BUILTIN_MODELS` 是 ADR-0015 引入的「管理员侧模型声明」，与家长 `ModelConfig` 并存。它带来三个具体代价：

1. **同一概念两处声明**：模型既有 env JSON 版本，又有 DB 版本；`GET /models` 要把两份合并成 `{builtin, custom}` 下发，前端要分两组渲染、两处拼标签（`（内置）` / `（默认）`）、选择器要 `[...builtin, ...custom]` 拼一次。四层样板换来的只是「管理员能预置模型」。
2. **孤儿路径**：内置模型不落库，因此**没有任何鉴权归属**——`resolve_engine(model_ref)` 用字符串 id 就能解析出引擎，走的是与家长模型完全不同的分支（`app/ai/engine.py` 原第 2 条优先级）。一条不经 `ModelConfig`、不经归属判定的引擎解析路径，是 ADR-0037/R2「归属判定只经单点」的反例。
3. **真实使用中它是空的**：默认值 `[]`，本地与容器都未配置。README 里的 Ollama 示例是唯一用例，而同一件事在「模型管理」UI 里做得更好（有服务商预设、有模型名建议、有加密存储、可设默认）。

## 决策

1. **删配置项**：`Settings.BUILTIN_MODELS` 移除（`app/core/config.py`）。
2. **删解析分支**：`app/ai/engine.py` 去掉 `_builtin_models()` / `list_builtin_models()` 与优先级第 2 条。`resolve_engine` 只剩两条：显式 `ModelConfig` id → 本家长 `is_default`。非 UUID 的引用一律视为查不到（`_as_uuid` 保留，仅作防御性转换）。
3. **删传输字段**：`ModelListResp` 只剩 `custom`（`app/features/model_management/schemas.py`）；`BuiltinModelInfo` 删除；`GET /models` 不再需要「合并两份来源」。
4. **前端对齐**：`ModelInfo.isBuiltin`、`ModelListResp.builtin` 删除；管理页取消「内置模型」分区，改为单一「我的模型」列表；选择器与管理页只遍历 `custom`。
5. **新增必填 api_key**：`ModelConfigCreate.api_key: str = Field(min_length=1)` + `field_validator` 去空白后非空。前端 `ModelCreateReq.apiKey` 由 `String?` 改为必填 `String`，表单在提交前拦截。编辑（`ModelConfigUpdate`）保持 `None` = 不修改的语义，但传空白串也拒绝（不允许用 `" "` 抹掉已有密钥）。
6. **连带修一个 422→500 的缺陷**：`RequestValidationError` 处理器把 pydantic 原始 `errors()` 直接交给 `jsonable_encoder`；pydantic v2 在自定义校验器抛 `ValueError` 时会把**异常对象本体**塞进 `ctx["error"]`，导致序列化失败、本该 422 的请求变成 500。新增 `_safe_validation_errors()` 只保留 `loc/msg/type`，ctx 内容字符串化（`app/core/errors.py`）。**任何**自定义校验器都会踩这个坑，不修的话第 5 条一上线就是 500。

## Consequences

- **单点真相**：模型来源只剩 `ModelConfig` 表，`resolve_engine` 的每条路径都必须带 `parent_id + session`（归属判定只经 Session 比对），不再有免鉴权的引擎解析入口。
- **API 破坏性变更**：`GET /models` 响应去掉 `builtin` 字段；`POST /models` 缺 `api_key` 由「接受」变 422。前端与之同步发布，无外部消费者。
- **`provider=ollama` 也要填 Key**：本地 Ollama 无鉴权，引擎构造时 `api_key` 本就不参与（`agent_core/adapters/genkit.py` 的 ollama 分支不收 key），所以强制必填只是让用户填个占位符（如 `ollama`）。这是为「一刀切、免分支」付的 UX 代价——换来的是表单/后端各少一条 provider 特例判断。若日后觉得烦，正确做法是给 ollama 加白名单豁免，而不是恢复内置目录。
- **运维面收窄**：少一个环境变量；`docker-compose.yml` 不再注入 `BUILTIN_MODELS`。密钥相关只剩 `MODEL_APIKEY_SECRET`（ADR-0038）。
- **测试基座变了**：真实模型 smoke 原先靠 `BUILTIN_MODELS` 提供 Ollama 端点（`tests/domain/test_llm_smoke.py`），改为自建一行 `ModelConfig` + 环境变量 `SMOKE_MODEL_NAME / SMOKE_MODEL_BASE_URL / SMOKE_MODEL_API_KEY`，顺带把「配置解析 → 引擎 → 出题契约」这条链路也纳入覆盖。
- **同步修正的历史遗留**：`backend/.env.example` 还在宣传早已删除的 `LLM_PROVIDER=mock` / `langchain`；根 `.env.example` 声称 `MODEL_APIKEY_SECRET` 留空是「进程内随机密钥，重启失效」——实际是回落 `SECRET_KEY` 派生（这正是 ADR-0038 事故的成因）。两份模板一并改写。
