# 04: 验证 P0 依赖环已消失

**What to build:** 端到端确认 home 与 courseware 之间不再存在特性互 import 内部的环，且 home 不再越权穿透 `assistant.domain`。

**Blocked by:** 01, 02, 03

**Status:** done

- [x] 定向 grep 全仓：`features/courseware` 下无 `package:kids_learn/features/home` import（回边已消失）；`features/home` 对 courseware 仅余前向（home_screen 引 courseware 屏幕、material_knowledge_manage_view 引 `courseware_recent_bar`），不构成环。
- [x] `home_notifier` 无 `assistant/domain` import（见 ticket-03）。
- [x] `flutter analyze` 全量通过；前端全量测试 552/552 通过。
- [x] `feature_relationship_tree.html` 的"循环依赖告警"改为"已解除"标注，并移除 SVG 循环路径、刷新 fe_courseware/fe_materials/fe_home 节点与关系清单。

_— 定位（volatile，仅供本次实施）—_
- 由 01/02/03 落地后做收口验证，无新代码改动，仅 grep 闸门 + 文档标注。
