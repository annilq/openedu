# 版权合规 CI 门禁

GitHub Actions `compliance.yml` 把版权合规检测接进 CI 发布前门禁：推 `main` / 开 PR 即跑后端 `pytest` → 版权合规检测，命中即 fail，阻断合并/发布。骨架期跑 `--self-test` 验证门禁逻辑，真实语料比对上线前启用。

- **门禁工作流**：`compliance.yml` 标题即「教材版权合规门禁 + 后端质量门禁（ADR-0019/ADR-0020）」，任何推 `main` 或开 PR 都触发（`github/workflows/compliance.yml:3`）。
- **后端质量门禁**：先 `uv run pytest` 跑后端测试，失败整轮红（`github/workflows/compliance.yml:32`）。
- **版权门禁（self-test）**：当前跑 `python scripts/copyright_compliance_check.py --self-test`，离线验证门禁逻辑可运行（不依赖外部语料）（`github/workflows/compliance.yml:35`）。
- **真实比对上线前启用**：导出题库 JSON → 比对 `protected_corpus/` 的两步已写好并注释，填好授权/公版参照后取消注释即生效（`github/workflows/compliance.yml:39`）。
- **文档同步说明**：README 与开发文档均记录 `compliance.yml` 为后端 pytest + 版权合规门禁，当前 `--self-test`、真实语料比对上线前启用（`README.md:160`、`docs/agents/development.md:103`）。

**Considered Options**：① 仅本地手动跑合规检测（易漏、不可控，拒绝）；② 接进 CI 门禁、命中阻断，骨架期先用 self-test（采用）。

**Consequences**：版权合规成为合入门禁，漏检不会随 PR 溜进 `main`；骨架期不因语料缺失误阻断，上线前补真实比对即闭环。门禁逻辑由 `--self-test` 持续守护，受保护原文不入库。
