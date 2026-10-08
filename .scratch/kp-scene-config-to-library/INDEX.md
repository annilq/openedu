# 知识点讲解配置迁移到场景库 · Tickets 索引

> 来源：ADR-0074（第 2 版）→ 本目录 7 个 tracer-bullet ticket。
> 发布形式：本地 `.scratch` 文件（未建 GitHub issue；`gh` 未登录）。后续 `gh auth login` 后可一键转 issue 并打 `ready-for-agent`。
> 术语以 `CONTEXT.md` 为准；每个 ticket 文件含 `What to build` / `Blocked by` / `Status: ready-for-agent` / 验收清单。

## 依赖链（blockers first）

```
01 后端 scene_template_config 表与默认图形读写 ──（无前置）
02 场景库内钻取收敛为单一 sealed 状态 ────────（无前置）
03 前端库详情页 kind 级图形画廊与默认图形标记 ─ 01
04 前端库详情页编辑已关联实例 ─────────────── 02
05 前端库详情页「关联知识点」新增实例 + seed ── 01, 02, 04
06 前端 KP 行移除「讲解」按钮 ─────────────── 04, 05
07 验证收尾：空态文案迁移 + 全量回归 ──────── 03, 04, 05, 06
```

## 最容易回归的断言（实施时不可省）
- **01**：`default_figure_key` 为空回落空占位，行为同现状；注册表 `SCENE_LIBRARY` 不被改为事实源
- **03/05**：设库默认图形只经 seed 注入新关联，绝不回写已落库 `kp.scenes` / `Question.scene_spec`（ADR-0073 快照不可变）
- **06**：撤按钮前 T04/T05 必须已落地，否则新 KP 进不了库

## 测试缝
- 主缝（后端）：`GET/PUT /materials/scene-library` + `PATCH …/scenes`，FastAPI TestClient + 临时 SQLite
- 次缝（前端）：`scene_library_detail_view` / `knowledge_point_row` widget 测试；扩展 `teacher_nav_single_source_test.dart` 守导航状态单一

## 转 GitHub issue 步骤（待登录）
1. `gh auth login`
2. 按编号顺序逐张建 issue，`Blocked by` 指向 blocking issue 编号
3. 全部打 `ready-for-agent` 标签

## Backlog（延后待办，不在本轮 7 票内）
- 「关联知识点」picker 端点取舍（纯前端过滤 vs 新增端点）——T05 已选纯前端过滤
- 「重置为库默认」UX——库内编辑实例时是否提供一键恢复库默认（遗留 4）
- 多 kind 导航状态——未来多 kind 时钻取仍须单一 sealed（遗留 2，T02 已先行收敛）
- per-kind 图形 allow-list 裁剪——§7 已明确不做
