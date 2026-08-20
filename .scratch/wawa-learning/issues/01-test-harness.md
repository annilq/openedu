# 01 — 测试基座：闭环 pytest 套件

**What to build:** 在 `full-stack-fastapi-template` 的 pytest 约定基础上，完善闭环主路径与错误路径契约测试，作为所有后续 ticket 的测试基准。无 langchain、无外部网络下即可全绿（mock 模式）。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

> **基线状态**：模板化后端已自带 `tests/conftest.py`（TestClient + SQLite 覆盖）和 `tests/api/routes/test_loop.py`（闭环 + 错误路径，2 passed）。本 ticket 在此基础上补充缺失项。

- [x] 一条命令可运行 pytest 套件，覆盖 register → add child → generate → today → answer → checkin → progress 主路径且全绿（**已实现**）
- [x] 错误路径契约测试：重复用户名注册返回 400；娃娃令牌调用家长接口返回 403；`GET /tasks/today` 中 `answer` 恒为 None；未认证请求返回 401（**已实现**）
- [x] 可在无 langchain、无外部网络环境下全绿（mock 模式）（**已验证**）
- [ ] 补充：MockProvider 返回非 JSON 时系统不崩并返回合理默认
- [ ] 补充：领域层单测——`Grader` 归一化（空格/大小写/标点）、`LLMProvider` 契约（fake provider 返回 `GeneratedQuestion`，验证 grading 委托正确）
- [ ] 补充：三条已修复 bug 的回归用例显式注释（pwdlib 替代 passlib、greenlet、`func.count().where` → `select(func.count()).where()`）
- [ ] 套件结构位于 `backend/tests/`，遵循模板 `conftest.py` + `tests/utils/` 约定
