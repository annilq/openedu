# 02: 素材册两环节（观察 + 探索）落地

**What to build:** 把课件 `cacb390…` 的环节 0（media_gallery「观察对称图形的基本特征」）与环节 3（media_gallery「探索对称轴与距离的关系」）从占位文本替换为**具体、可投屏**的素材与引导语。

**Blocked by:** 01

**Status:** ready-for-agent

**环节 0（观察）**
- [ ] `payload.items[].image` 从「教师可上传一张简单的轴对称图形…」替换为具体 CC0 图（正方形/菱形/风车/蝴蝶任选 2–3 张，按 T08 入库为 `platform_cc0` 或引用已有素材）。
- [ ] `payload.prompt` 改写为具体可答问题："这些图形沿哪条直线对折后能完全重合？这条直线叫什么？"
- [ ] `script` 保留启发式提问，去掉「教师可上传」措辞。

**环节 3（探索）**
- [ ] `payload.items[].image` 替换为「对称点 A 与 A' 及其对称轴、标注距离=3 小格」的具体图。
- [ ] `payload.prompt` 改写为："量一量 A 和 A' 到对称轴的距离，你发现了什么？"（预期答：相等）。
- [ ] 与 01 术语表对齐「对应点 / 距离相等」表述。

**验收**
- [ ] 两个 media_gallery 环节不再含「教师可上传 / 教师可示例」占位字样。
- [ ] 引用的素材在 `coursewareasset` 表存在且 `source=platform_cc0`（或已确认可显示）。
- [ ] `flutter analyze` / 课件演示端能正确渲染两张图与引导语。
