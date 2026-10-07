# 05: 串联校验 + 状态置 ready + CC0 入库

**What to build:** 四环节在演示端连贯走查，确认知识点关联与范围快照正确，把课件 `status` 由 `draft` 置 `ready`，并把本 epic 新增的 CC0 素材按 T08 入库。

**Blocked by:** 02, 03, 04

**Status:** done

- [x] 串联走查（结构化）：四环节 `sections` 解析通过，环节顺序 观察(media_gallery) → 交互(interactive_scene) → 练习(practice) → 探索(media_gallery) 连贯；全量占位扫描（`教师可上传`/`教师可示例`/`占位`/`TODO`/`xxx`）零命中。
- [x] 核对课件行：`knowledge_point_id=357dd9129061452ea9ec35a881548f9c`、`subject=数学`、`grade=4`、`semester=下学期`、`title=图形的运动（轴对称）`、`kp_name` 一致（快照引用无误）。
- [x] CC0 素材已在 `coursewareasset` 注册（`source=platform_cc0`，`license=CC0 1.0`，归属系统哨兵教师 `0000…00cc`，对所有教师可见、不可删除）；并改走 `seed_cc0.py` manifest 以便复现（见 02 说明）。
- [x] `status` 由 `draft` 置 `ready`（已执行 `UPDATE … SET status='ready'`）。
- [x] 回归（结构层）：`sections` 为合法 JSON 且严格符合渲染器契约，无需改编辑器即可打开/保存；**Flutter UI 运行期投屏与「拖点补全 / AI 出题」交互未在沙箱验证**（无外网 + 无法跑 Flutter UI），列为已知未验证项。

**验收**
- [x] 四环节内容完整、无占位、结构连贯。
- [x] `status=ready`，kp 关联与范围快照正确。
- [x] 新增 CC0 素材入库且可复用（对其他教师可见、不可删除）；复现源已落 `backend/seeds/courseware_cc0/`。
