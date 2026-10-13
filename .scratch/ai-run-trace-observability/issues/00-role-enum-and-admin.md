# Ticket 00 — 账户角色枚举化与 admin 落地

- **What to build**: 把账户角色从自由字符串改为有类型的 `Role(student / teacher / admin)`；数据库列保持 `VARCHAR(16)`（不生成原生枚举迁移）；全仓账户角色比较改为 `Role.*`；新增 `require_admin` 与 `require_owned_or_admin`（admin 越教师边界只读审计）；把运行轨迹 debug 端点接通 admin（admin 看全部、教师只看自家，`teacher_id=None` 表示全部）；启动期环境变量驱动 seed 一个默认管理员（`ADMIN_SEED_USERNAME` + `ADMIN_SEED_PASSWORD` 两者皆配才创建，绝不写死口令）。admin = 超级教师，复用 teacher 调用面，经 `_surface_of(role)` 折算后再传入 `agent_core`，绝不污染其业务无关性。
- **Blocked by**: —
- **Status**: ✅ done（2026-10-12，本轮回合已落地并测过）
- **验收清单**:
  - `Role` 枚举三值齐备；DB `user.role` 列仍为 `VARCHAR(16)`；历史字符串 `teacher/student` 读写自动互转、`admin` 新值可落库。
  - 全仓账户角色比较无残留自由字符串（仅 `Message.role` 的 system/user/assistant/tool 与 `agent_core` surface 字符串保留）。
  - `require_teacher` 放行 `(TEACHER, ADMIN)`；`require_admin` 仅 admin；`require_owned_or_admin` 让 admin 越教师边界只读。
  - debug 端点：admin 调 `GET /ai/debug/conversations` 返回全部教师、教师只返回自家；详情走 `require_owned_or_admin`，越权 403。
  - admin 种子仅当环境变量两者皆配才创建，启动期幂等；口令绝不写死。
  - `agent_core` 零 `app.*` 依赖、无 `Role` import（`tests/ai/test_layering_invariants.py` 不破）。
  - `pytest` 全量 791 passed / 2 skipped；`ruff check` 改动文件全绿。

> 落库 commit 见 git HEAD（ai-intent-routing 集成分支）。类型形状（编码分离决策）：`Role(str,Enum)`；`_surface_of(role)` 仅 `STUDENT` 走 student 面、其余（含 ADMIN）走 teacher 面后传入 `agent_core`。
