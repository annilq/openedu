# 场景库：讲解配置唯一管理面（ADR-0074 v4）

> 来源 ADR：`docs/adr/0074-kp-scene-config-to-library.md`（v4，草案）
> 模型：场景（kind）服务端硬编码，前端「新增场景」仅提醒开发者；教师配置已有 kind 的
> 演示图形 + 关联知识点(1:N) + 按 KP 编辑标题。事实源 `kp.scenes` 不变（ADR-0073）。

## Tickets（依赖序，blockers first）

| ID | 标题 | Blocked by | Status |
|----|------|-----------|--------|
| 01 | 后端 `scene_template_config` 表 + 默认图形读写 + 库聚合 prune 标记 | — | done |
| 02 | 导航：场景库内钻取收敛为单一 sealed 状态 | — | done |
| 03 | 前端库详情：演示图形画廊 + 默认标记 + 「新增场景」提醒 | 01 | done |
| 04 | 前端库详情：关联知识点(1:N) + 标题编辑 + 解除关联 | 01, 02 | done |
| 05 | 前端 KP 行移除「讲解」按钮 | 04 | ready-for-agent |
| 06 | 验证收尾：空态文案迁移 + 全量回归 | 03, 04, 05 | done |

## 决策锚点（写进每张 ticket）

- 事实源不变：`scenes` 唯一事实源，渲染/出题/课件永不回查库配置（ADR-0073）。
- 场景服务端硬编码：前端「新增场景」只弹开发者提醒，不调写端点、不产生 kind。
- 默认图形只 seed：库改默认只影响新关联 KP，绝不回写已落库 `kp.scenes`/`Question.scene_spec`。
- 关联由 `kp.scenes` 的 `kind` 隐式表达，无新增关联表；seed 经现有 `PATCH …/scenes`。
- prune 处理：KP 被清理后库侧标悬空、可解除，不级联删场景。
- T05 必须等 T04：撤 KP 按钮前库须具备关联/编辑能力，否则新 KP 进不了库。

## 最容易回归的断言（实施时不可省）

- **01**：`default_figure_key` 为空回落空占位，行为同现状；注册表 `SCENE_LIBRARY` 不被改为事实源。
- **03**：点「新增场景」弹开发者提醒、无写调用、不产生 kind。
- **04**：设库默认图形只经 seed 注入新关联，绝不回写已落库 `kp.scenes`/`Question.scene_spec`（ADR-0073 快照不可变）。
- **05**：撤按钮前 T04 必须已落地，否则新 KP 进不了库。

## 测试缝

- 主缝（后端）：`GET/PUT /materials/scene-library` + `PATCH …/scenes`，FastAPI TestClient + 临时 SQLite。
- 次缝（前端）：`scene_library_view` / `scene_library_detail_view` / `knowledge_point_row` widget 测试；
  扩展 `teacher_nav_single_source_test.dart` 守导航状态单一（T02）。

## 转 GitHub issue 步骤（待登录）

1. `gh auth login`
2. 按编号顺序逐张建 issue，`Blocked by` 指向 blocking issue 编号
3. 全部打 `ready-for-agent` 标签

## Backlog（延后待办，不在本轮 6 票内）

- 同步到已关联（显式按钮，非 live binding）——改库默认/标题一键推到已关联 KP
- per-kind 图形 allow-list 裁剪——已定不裁剪
- 关联后是否立即开编辑器——写入 seed 后直接弹编辑器 vs 先回列表
- 库聚合 prune 标记展示文案
