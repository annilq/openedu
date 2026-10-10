# 01: 图库表与内置种子 + 读端点

**What to build:** 建立图库持久层——把内置图形从后端 Python 常量搬进数据库，并提供按需读取的端点。教师/用户后续在画板上设计的图形也落入同一张表。这是整案的基础，先行。

**Blocked by:** 无（可立即开工；本票是整案基础，先行）

**Status:** done

## 范围
- 新增 `figure_library` 表，字段仅几何：`key`、`label`、`points`（归一化顶点 `[[x,y],…]`）、`edges`（连接关系 `[[i,j],…]`）、`note`、`is_builtin`。**不含任何 axis 字段**（对称纯视觉判定，ADR-0083 决策 2）。
- 迁移把现行 `FIGURES`（`scene_figures.py`）的 11 个内置图形以 points+edges 入库，`is_builtin=true`。
- `GET /scene-library/figures` 改为读 DB 返回全部行（内置 + 用户），结构含 `key/label/points/edges/note/is_builtin`。

## 验收
- [x] 迁移后 `figure_library` 表存在，含 11 条 `is_builtin=true` 行。
- [x] 每条内置行带完整 `points`/`edges`，且与现行 `FIGURES` 逐点一致（迁移校验脚本/测试断言）。
- [x] `GET /scene-library/figures` 返回 DB 行（≥11 条），字段齐全，无 axis 字段泄漏。
- [x] 测试断言：读取不依赖前端 const、不触发本地缓存。
- [x] 旧代码 `FIGURES` 常量**保留**（本票不删，由 06 收口），但 `default_scene_from_figure` 尚未切换（切换在 02）。

## 实施记录（2026-10-10，worktree /private/tmp/oedu-figlib）
- 分支 `feature/figure-library-db`（基于 HEAD 1e150c9）。从别人的 `ai-intent-routing` worktree 迁出，避免污染他人工作区。
- 改动：`material.py` 新增 `FigureLibrary` 表（points/edges 用 `JSON(none_as_null=True)`）；`db.py` 的 `init_db` 末尾加 `_seed_figure_library()`（ORM 写 11 内置行，edges=`[[i,(i+1)%n]`，幂等）；`service.list_figure_library(session)` 改读 DB；`router` 端点传 `session`；`schemas.FigureLibraryItem` 删 axis 字段、加 `edges/note/is_builtin`。
- 验证：ruff 全绿；`tests/features/materials/test_scene_figures.py` 16 passed（含 parity 锁测试，figures.dart 未改故仍过）；`test_figure_library_service_matches_source` 改为顺序无关比较。
- 下一步 frontier = T02（SceneSpec 形态改造，跨前后端单切片）。

## 纪律
- 不引入写端点（POST 在 04）。
- 不改动 SceneSpec 形态（那是 02）。
