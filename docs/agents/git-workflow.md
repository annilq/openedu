# 变更纪律 / Git 流程 — 娃娃学习 App

## 核心纪律

> **架构变更先改文档与 ADR，再改代码。**（正常开发流程，见 `../architecture/项目分析_架构规范与业务功能.md` §2.1）

任何影响分层、数据模型、API 契约、设计系统的改动，先更新对应文档与 ADR，再落地代码。文档与代码保持同步是该项目的硬要求（已多次整改验证）。

## ADR 机制

- 后端决策记录在 `docs/decisions/娃娃学习App_ADR.md`（ADR-001..013，现已归至 docs/decisions/）。
- 前端代码组织 / 设计决策记录在 `frontend/docs/adr/`（0001..0004），`Status` 有 `Accepted` / `Draft`。
- 新增决策写新 ADR；推翻旧决策时在新 ADR 的 `Supersedes` 字段显式声明（参考 ADR-0002 推翻「暖绿为默认」、ADR-0003 推翻 ADR-0002 的「保留暖绿备选」）。

## 完成门禁（Done Definition）

后端：
- `uv run ruff check .` 全过；`uv run pytest` 通过（含新增测试）。
- 新端点 / 模型变更同步更新 `../architecture/技术架构_后端.md` 与 ADR。

前端：
- `flutter analyze` **零警告**（每阶段硬性门禁）。
- `flutter test` 通过；状态机改动补 `mocktail` 测试。
- 单文件 ≤ 300 行；超标先拆再合入。

## AI 代理协作建议

- 优先直接改文件解决问题，改完跑对应门禁命令验证。
- 跨模块的「草稿 / 锁定 / 派发」「题库复用」「级联安全」等语义改动，参考 `../architecture/实施文档_题库复用闭环_*.md`。
