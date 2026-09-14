# 引擎失败归因与密钥解密契约：密文永不出门、401 永不说成「不支持工具调用」

用户在娃娃端提问，看到的是「**当前模型不支持工具调用**：GenkitError: INTERNAL: Error while running action openai/deepseek-v4-flash: Error code: 401 - Authentication Fails, Your api key: ****xOOR is invalid」。三层缺陷叠出来的假象：真因是**密钥解不开导致 Fernet 密文被当成 API Key 发给厂商**（`****xOOR` 正是密文尾号，不是任何真实密钥的尾号），而错误被 `agent_core` 无差别包成「模型没有 function calling 能力」。本 ADR 固化两条契约：**密文永不出门**（解不开就是「没有密钥」）、**厂商失败与能力缺失各归其类**。

## 规则

1. **`decrypt()` 解不开只能返回 `None`**（`backend/app/core/crypto.py:45`）。密文损坏 / 密钥轮换时返回原文，等于把密文当凭据发给第三方——既是功能故障（401）也是**凭据外泄**。完全未配置密钥时的明文兜底（`_fernet() is None` → 原样返回）保留，那是另一条分支。
2. **失败按根因分两类，不得混用**：
   - 模型没有 function calling → `ToolUnsupportedError` → `ERROR(code="TOOL_UNSUPPORTED")`（ADR-0033 不退化）；
   - 厂商拒绝请求（认证 / 限流 / 网络 / 参数被拒）→ `ProviderRequestError(kind=…)` → `ERROR(code="PROVIDER_ERROR")`（`backend/agent_core/errors.py:23`）。
   分类默认必须落在后者（`agent_core/adapters/genkit.py:376`）：把 401 说成能力问题，会让用户去换模型，而真问题是密钥。
3. **三类失败一律硬失败**：不静默降级为纯文本、不重试、不继续（同 ADR-0033 的精神）。区别只在于**话怎么说**。
4. **用户看到的提示是策展文案，原始厂商报文只进日志**（`ProviderRequestError.user_hint`）：认证 → 「API Key 无效或已过期，请在「模型管理」中重新填写该模型的密钥」；限流 / 网络各有其话。原始报文既冗长（整段 JSON）又可能带回被拒凭据的尾号。
5. **上层不得用 `except Exception` 把引擎失败抹成「请添加模型」**：出题 / 批改路径必须先按 `ProviderRequestError` 分流（`app/features/tasks/service.py:309`、`:400`、`:1110`、`app/features/review/service.py:96`），HTTP 语义走 `ErrCode.LLM_REQUEST_FAILED`（`app/core/errors.py:35`，502）。

## 本决策依据

- **事故链条（可复现）**：`ModelConfig.api_key_enc` 是 Fernet 密文（`app/db/models/model_config.py:19`）。旧密文用 `SECRET_KEY=dev-secret-change-me` 加密，该值来自仓库根 `.env`；而 `app/core/config.py:12` 明确根 `.env` 已弃用、优先读 `backend/.env`——根 `.env` 改名后 `SECRET_KEY` 静默回落默认值 `changeme`（`config.py:20`），于是 `decrypt` 抛 `InvalidToken`，旧实现 `return token`（原 `crypto.py:44`）把密文交出去。实测：用 `dev-secret-change-me` 可解出与该家长 `DEEPSEEK_API_KEY` 一致的明文（尾号 `f474`），用 `changeme` 解不开——密文尾号 `IIcCxOOR` 与厂商回包 `****xOOR` 对上。
- **误归因点（本次修复）**：`agent_core/adapters/genkit.py:532` 原为 `except Exception as exc: raise ToolUnsupportedError(_failure_reason(exc))`——工具路径上**任何**引擎异常（401 / 429 / 网络）都被贴上「模型能力」标签。ADR-0033 的硬失败决策是对的，错的是把「任意失败」等同于「能力缺失」。
- **三条分支都要归类**：schema（出题，`genkit.py:461`）、tools（`:533`）、纯文本（伴学，`:480`）。只修工具分支的话，出题路径的 401 会以原始 `GenkitError` 冒到顶层，被兜底 500 抹成「服务器内部错误」（`app/core/errors.py:202`）。
- **旁路 `grade_open` 自行归类**：它直接调 `engine.genkit.generate`（不经适配器 stream，`app/domain/genkit_provider.py:113`），故复用 `classify_failure` 显式归类，否则同一个 401 在 chat 与批改两处会被说成两回事。
- **守卫位置**：`agent_core/subagent.py:237`（tool loop）、`agent_core/runtime.py:141`（subagent 之外的失败出口）双点兜底，保证 `ProviderRequestError` 在任何路径都不会漏成 `AGENT_ERROR` 的「助手执行出错：…」。
- **既有测试钉错了行为**：`tests/ai/test_genkit_adapter_tools.py` 原断言 `RuntimeError("connection reset")` → `ToolUnsupportedError`（网络故障被说成能力问题），本次按 ADR 改为 `ProviderRequestError(kind="network")`；该用例真正要守的不变量（**已吐部分文本也必须硬抛、不得改当纯文本答完**）保持不变。
- **回归钉死**：`tests/ai/test_provider_failure_attribution.py` 以剪切板原文为固定输入，断言 401 → `kind="auth"`、`user_hint` 含「API Key」且不含「不支持工具调用」；并断言存储密文**永不出现在**传给引擎的参数里（`test_resolve_engine_never_passes_stored_ciphertext_as_api_key`），同时反向断言密钥匹配时明文密钥真的传出去了（别把「安全」修成「一直没密钥」）。

**Considered Options**：① 只改文案（把「不支持工具调用」改得中性些）——根因（密文外泄 + 归因错）都还在，拒绝；② `decrypt` 失败时抛异常、让整个模型解析失败——密钥轮换会让**所有**已存模型直接不可用，而 `resolve_engine` 的 `None` 语义已被「未配置模型」占用，改契约的爆炸半径远大于收益，拒绝；③ 保留「一律 ToolUnsupportedError」并在上层加词法判断——判断散落多处必然漂移，拒绝；④ 密文一律返回 `None`（采用）+ 适配器 `classify_failure` 单一归类点（采用）+ `user_hint` 挂在异常类型上（采用）。

**Consequences**：密钥轮换后的表现从「玄学 401 + 密文外泄」变成「一条可操作提示 + 服务端 warning 日志」，用户按提示重填密钥即可恢复；`kind` 词法表（`genkit.py:337-371`）是**启发式**，新增厂商时可能要补标记词——未命中的一律落 `unknown` 并带上原始原因，绝不误报成能力问题。遗留（未做，需另起）：① **启动期密钥健康检查**——当前仍无任何主动告警，家长要等到提问失败才知道密钥失效（可考虑 `init_db` 后扫描 `ModelConfig` 并 warn）；② `SECRET_KEY` 仍可被默认值顶替（`MODEL_APIKEY_SECRET` 未配置时用它派生 Fernet 密钥），生产部署应显式配置前者，文档已提示但无强制。
