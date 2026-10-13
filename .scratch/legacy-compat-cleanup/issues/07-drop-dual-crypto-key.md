# 07: 移除 crypto 双密钥回退

**What to build:** api_key 加解密只认 `MODEL_APIKEY_SECRET` 单一密钥来源；去掉 `MODEL_APIKEY_SECRET or SECRET_KEY` 的静默回退（该回退会在未配专用密钥时落到通用 `SECRET_KEY`，属静默降安全级）。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `crypto` 模块不再引用 `SECRET_KEY` 作为回退。
- [ ] 有 `MODEL_APIKEY_SECRET` 时正常派生密钥；缺失时：DEV 环境警告并明文、非 DEV 环境启动失败（fail-fast）。
- [ ] `decrypt` 解不开仍只返 `None`（ADR-0038 不变）。
- [ ] 后端 pytest 相关用例通过（新增/调整 `_fernet` 单测）。

_— 定位（volatile，仅供本次实施）—_
- `backend/app/core/crypto.py:28` `MODEL_APIKEY_SECRET or SECRET_KEY`
