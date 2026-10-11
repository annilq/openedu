# Ticket 04 — 班级下钻页（参数化 `StudentManagementScreen`：查看 / 筛选 / 返回 + 班内查看 / 移班 / 删除）

- **What to build**: 复用既有 `StudentManagementScreen`，新增构造参数 `classId`（`String?`）做参数化（**不**再造一份学生列表）。`classId != null` 时：`GET /students?class_id=` 加载、隐藏"全部/各班/未分班"筛选 chip、标题「{班级名} · N 人」、返回回到班级管理列表。班内操作（均用既有端点，**不**依赖后端 class_id 扩展 ticket 05，故可与 05 并行）：查看名册（搜索走 `GET /students?class_id=&keyword=`）、批量移班（复用 `POST /students/batch-reassign`）、删除学生（级联清理，后端已就绪）。**班内"单个添加 + 导入归入本班"不在此票，见 ticket 06。**
- **Blocked by**: 03
- **Status**: ✅ done（2026-10-11，本轮回合已落地并测过）
- **验收清单**:
  - 参数化行为：`classId == null` 时保持原学生管理（全量 + 未分班、显示筛选 chip、标题「学生管理 · N 人」、添加/导入不预填班级）；`classId != null` 时上述切换全部正确。
  - 下钻落点：从 ticket 03 的班级卡片进入，加载该班学生、标题含班级名、返回回到班级管理列表（走单一回落出口，不用裸 `Navigator.pop`）。
  - 班内查看名册、批量移班、删除学生：复用既有端点，行为与原学生管理一致。
  - 文件规模棘轮：改动若逼近 400 行基线则抽 part，不调高基线。
  - 全站禁 Material 控件：下钻页在不套 Material 的树里真构建。
