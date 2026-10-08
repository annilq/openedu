# 05: 前端库详情页「关联知识点」新增实例并 seed 注入默认图形

**What to build:** 教师在库详情页用「关联知识点」入口，把一个尚未关联某 kind 的知识点加进该场景：前端从教师域 KP 列表过滤掉已关联该 kind 的项（纯前端过滤，零新增端点），选一个未关联 KP，写一份 seed 场景（kind + 注册表中性轴参数 + `figure/points` 取自 T01 的 `default_figure_key`，空则回落空占位）经 `PATCH …/scenes` 进库，使其出现在库清单。实现 ADR-0074 §1「新增关联」+ §4。这是撤掉 KP 行「讲解」按钮（T06）的前置——有了它，新 KP 才有入口进库。

**Blocked by:** 01, 02, 04

**Status:** ready-for-agent

- [ ] 库详情页有「关联知识点」入口，打开 picker 列出教师域 KP、前端过滤已关联该 kind 的项
- [ ] 选一个未关联 KP 后，构造 seed 场景（kind + 中性轴 90°/位 0.5 + figure/points 取自 `default_figure_key`，空则回落空占位）
- [ ] seed 经 `PATCH …/scenes` 写入该 KP，断言其进入库 `associated_knowledge_points` 列表
- [ ] 关联后该 KP 在库内可经 T04 编辑、可覆盖图形（house→butterfly），不影响库默认与其他 KP
- [ ] 纯前端过滤 KP 列表，不新增后端端点（遗留 1 倾向方案）
- [ ] `flutter analyze` 零 issue；「关联知识点」widget 测试覆盖过滤+写入

**决策锚点：** ADR-0073（seed 注入图形不构成 live binding、scenes 存完整副本）、ADR-0074 §1/§4/§7（关联写 seed 图形取自默认、保留 KP 可覆盖、不回写已落库）。
