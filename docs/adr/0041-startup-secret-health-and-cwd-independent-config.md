# ADR-0041 启动期密钥健康检查与配置 CWD 无关化

## 背景

早期架构评审与 401 密钥事故（ADR-0038）暴露两类配置脆弱点：

- `SECRET_KEY` 长期沿用默认 `changeme`，JWT 签名密钥不安全；换密钥会使已有登录态失效，于是长期不敢改。
- 密钥问题（密钥轮换 / `MODEL_APIKEY_SECRET` 缺失）只在用户提问时才以 401 暴露，且密文曾被当凭据外泄（`xOOR` 现场）。
- `DATABASE_URL` 默认 `sqlite:///./app.db` 随进程 CWD 漂移，换目录指向另一库（与 ADR-0038 的 env_file 漂移同类）。

## 决策

**启动时消除不安全默认与 CWD 漂移，并把密钥问题提前到启动期。**

- **SECRET_KEY 持久化**：未显式配置时，首次启动生成随机密钥并落盘 `backend/.secret_key`（gitignore），后续复用（`app/core/config.py:23` `resolve_effective_secret_key`；`config.py:95` `_resolve_secret_key` 校验器）。文件系统只读时退化为内存随机值并告警（仅应急）。
- **DATABASE_URL CWD 无关**：默认值即 `backend/` 下绝对路径（`config.py:87`）；相对 SQLite 路径在 `_normalize_db_url`（`config.py:46`）统一解析为 `backend/` 下绝对路径。
- **启动期密钥健康检查**：`app/main.py:22` 的 lifespan 在 `init_db()` 后调用 `check_runtime_secrets_health`（`app/core/secrets.py:21`）：
  - 生产环境 `SECRET_KEY` 为默认/空 或 `MODEL_APIKEY_SECRET` 为空 → 直接抛错阻断启动；开发环境仅告警。
  - 对每张 `ModelConfig` 尝试解密 `api_key_enc`，解不开（密钥轮换）即记 WARNING 并点名模型 id，提问/出题时按未配置处理，而非运行时 401。

## Considered Options

- **密钥健康检查放请求期 vs 启动期**：选启动期——失败更早、可观测、避免污染用户请求。
- **SECRET_KEY 每次随机 vs 持久化**：选持久化落盘——兼顾「非默认」与「登录态跨重启稳定」。
- **DATABASE_URL 改绝对路径 vs 依赖调用方传绝对值**：选默认值即绝对——与 env_file 修复同族，调用方零改动。

## Consequences

- 不再有 `changeme` 默认密钥；生产缺配启动即失败，而非静默不安全。
- 密钥轮换在启动日志可见，排障前移。
- 新增 `backend/.secret_key`（gitignore）；`MODEL_APIKEY_SECRET` 在生产环境变为**强约束**（缺失即阻断启动）。
- 测试用 `conftest` 已覆盖绝对路径 `DATABASE_URL`（`tests/conftest.py:11`），默认值变更不影响测试。
