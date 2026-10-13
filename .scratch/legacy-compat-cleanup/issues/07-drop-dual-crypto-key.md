# 07: 移除 crypto 双密钥回退

**What to build:** api_key 加解密只认 `MODEL_APIKEY_SECRET` 单一密钥来源；去掉 `MODEL_APIKEY_SECRET or SECRET_KEY` 的静默回退（该回退会在未配专用密钥时落到通用 `SECRET_KEY`，属静默降安全级）。

**Blocked by:** None

**Status:** done

## 验收清单

- [x] `crypto` 模块不再引用 `SECRET_KEY` 作为回退（grep `or SECRET_KEY` 后端零命中；`_fernet` 仅读 `settings.MODEL_APIKEY_SECRET`）。
- [x] 有 `MODEL_APIKEY_SECRET` 时正常派生密钥；缺失时：DEV 环境 warning + 明文兜底（`_fernet` 返 `None`，与 `encrypt`/`decrypt` 对称）、非 DEV 环境抛 `CryptoConfigError` fail-fast（由 lifespan `check_runtime_secrets_health` 启动期阻断）。
- [x] `decrypt` 解不开仍只返 `None`（ADR-0038 不变）。
- [x] 后端 pytest 相关用例通过：`tests/core/test_crypto.py` 5 passed（覆盖 `_fernet` 三态 + 密钥轮换 decrypt→None + 明文兜底）；依赖旧回退的 `test_provider_failure_attribution.py` / `test_models.py` 已显式配置 `MODEL_APIKEY_SECRET`。

## 实施说明（commit `48660b8`，已由并行会话落地，本轮仅核验 + 回写 tracker）

- `_fernet()` 原 `secret = settings.MODEL_APIKEY_SECRET or settings.SECRET_KEY` → 改为仅 `settings.MODEL_APIKEY_SECRET`，缺失分支按环境分流（DEV 明文 / 非 DEV 抛 `CryptoConfigError`）。
- 新增 `tests/core/test_crypto.py`（60 行）：显式覆盖三态 + 密钥轮换。
- 模块 docstring 重写：明确「唯一来源」「解密失败契约 ADR-0038」。
- **跨核验结论**：代码与测试已在 `48660b8` 落地并通过；tracker 此前标 `ready-for-agent` 属陈旧状态，本轮按实测回写为 done。
