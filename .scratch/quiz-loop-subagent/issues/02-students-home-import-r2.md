# Ticket 02 — 修 students → home 横向 import 违反 R2

- **What to build**: 学生管理页横向 import 了 home，违反分层单向规则（`main/ → features/* → shared/*`；跨 feature 复用应下沉 `shared/` 或经 home 装配）。本票消除该 import，让 feature_boundaries R2 守卫恢复绿，学生管理功能行为不变。
- **Blocked by**: —（无，可立即开始）
- **Status**: ready-for-agent
- **验收清单**:
  - [ ] 学生管理页对 home 的 import 消除；消除方式（下沉 `shared/` 或经 home 装配注入）在提交正文说明选择理由
  - [ ] `feature_boundaries_test.dart` R2 守卫恢复绿（干净树上当前实际:`students -> home` 1 处）
  - [ ] 学生管理页既有 widget / provider 测试 0 回归
  - [ ] 不把 home 的无关内容倒灌进 `shared/`——只搬被复用能力，搬完在 shared 侧不产生对 features 的反向依赖

## 决策锚点

- **规则同源**：feature 间横向依赖会引发循环依赖，后端同规则见 ADR-0027；前端单向分层见 ADR-0036/0037。
- **「经 home 装配」的正确形态**：由 home 层把回调 / 导航目标注入学生管理页，不是让学生管理页反向 import home——后者正是当前违规。
- **归因前提**：该红在当前 HEAD（`c2d98c2`）干净 worktree 复现，属既存账，不是本轮判断题重构引入（本重构未触碰 students 区域）。
