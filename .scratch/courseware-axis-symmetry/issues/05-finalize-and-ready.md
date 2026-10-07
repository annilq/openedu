# 05: 串联校验 + 状态置 ready + CC0 入库

**What to build:** 四环节在演示端连贯走查，确认知识点关联与范围快照正确，把课件 `status` 由 `draft` 置 `ready`，并把本 epic 新增的 CC0 素材按 T08 入库。

**Blocked by:** 02, 03, 04

**Status:** ready-for-agent

- [ ] 演示端按 观察 → 交互 → 练习 → 探索 顺序走查一遍，环节衔接顺畅、无占位字样残留。
- [ ] 核对课件行：`knowledge_point_id=357dd9129061452ea9ec35a881548f9c`、`subject=数学`、`grade=4`、`semester=下学期`、`title=图形的运动（轴对称）` 均正确（快照引用无误）。
- [ ] 02 中新增的 CC0 素材按 T08 入库 `coursewareasset`（`source=platform_cc0`，填 `source_url` / `license`），不绑定私人教师。
- [ ] 将 `status` 由 `draft` 置 `ready`（演示不阻塞，但列表筛选应显示「可上台」）。
- [ ] 回归：课件编辑器仍能正常打开/保存本课件（与 `courseware-round-2` 编辑器能力不冲突）。

**验收**
- [ ] 四环节内容完整、无占位、演示连贯。
- [ ] `status=ready`，kp 关联与范围快照正确。
- [ ] 新增 CC0 素材入库且可复用（对其他教师可见、不可删除）。
