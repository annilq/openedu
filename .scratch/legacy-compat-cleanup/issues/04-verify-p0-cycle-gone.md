# 04: 验证 P0 依赖环已消失

**What to build:** 端到端确认 home 与 courseware 之间不再存在特性互 import 内部的环，且 home 不再越权穿透 `assistant.domain`。

**Blocked by:** 01, 02, 03

**Status:** ready-for-agent

- [ ] 定向 grep 全仓：`features/courseware` 下无 `package:kids_learn/features/home` import；`features/home` 下无回边到 courseware 内部（仅前向合法）。
- [ ] `home_notifier` 无 `assistant/domain` import。
- [ ] `flutter analyze` 通过。
- [ ] 在 `feature_relationship_tree.html` 的"循环依赖告警"处注明该环已解除。

_— 定位（volatile，仅供本次实施）—_
- 由 01/02/03 落地后做收口验证，无新代码改动，仅 grep 闸门 + 文档标注。
