# 教师端规模化 · Tickets 索引

> 来源：ADR-0068/0069/0070 → spec `docs/specs/*` → 本目录 16 个 tracer-bullet ticket。
> 发布形式：本地 `.scratch` 文件（未建 GitHub issue；`gh` 未登录）。后续 `gh auth login` 后可一键转 issue 并打 `ready-for-agent`。
> 术语以 `CONTEXT.md` 为准；每个 ticket 文件含 `What to build` / `Blocked by` / `Status: ready-for-agent` / 验收清单。

## 依赖链（blockers first）

```
A 系列 · 班级与学生管理（ADR-0068）
  01 班级实体与 CRUD ──────────────┐（无前置）
  02 学生管理页与列表过滤/搜索 ─── A1
  03 批量移入/移出班级 ────────── A1, A2
  04 删除学生账号与级联清理 ───── A1
  05 Excel 导入端点 ───────────── A1
  06 Excel 导入 UI ────────────── A5
  07 账号表导出 ───────────────── A1

B 系列 · 批量派发（ADR-0069）
  08 作业派发对象关系与批量派发 ─ A1
  09 答题/打卡/今日任务校验改造 ─ B1
  10 派发对象列表与任务列表聚合 ─ B1

C 系列 · 导航与统计（ADR-0070）
  11 学情统计聚合端点 ─────────── A1
  12 统计页 UI ───────────────── C1
  13 学生详情页（页签） ────────（无前置）✅ done
  14 六处消费方脱离全局学生状态 ─ B3, C3
  15 删除 selectedStudentProvider ─ C4a
  16 侧栏改八项 ─────────────── C4b, A2, C2
```

> C6（概览页改教师工作台，待办聚合）按 spec 建议先出原型、延后单独排期，不在本轮 16 票内。

## 最容易回归的断言（实施时不可省）
- **09**：非派发对象答题必须 403；只完成一半时任务仍「已派发」且未完成的能作答
- **11**：孤儿错题归「未知」并标注数量；空学期归「整学年」不单列；题目年级与学生年级**不**共用下拉；大班(≥60)响应时间作为批量聚合判据
- **15**：`flutter analyze` 零错误（残留 `selectedStudentProvider` 引用即漏改）

## 测试缝
- 主缝：REST 端点（FastAPI TestClient + 临时 SQLite，夹具 `backend/tests/conftest.py`，身份 `tests/utils/user.py`）
- 次缝：扩展 `frontend/test/teacher_nav_single_source_test.dart`（不新建）

## 转 GitHub issue 步骤（待登录）
1. `gh auth login`
2. 按编号顺序逐张建 issue，`Blocked by` 指向 blocking issue 编号
3. 全部打 `ready-for-agent` 标签
