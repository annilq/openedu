# 02: 素材册两环节（观察 + 探索）落地

**What to build:** 把课件 `cacb390…` 的环节 0（media_gallery「观察对称图形的基本特征」）与环节 3（media_gallery「探索对称轴与距离的关系」）从占位文本替换为**具体、可投屏**的素材与引导语。

**Blocked by:** 01

**Status:** done

**环节 0（观察）**
- [x] `payload.items[]` 改为 `{asset_id, caption}`（渲染器契约），引用 3 张 `platform_cc0` 对称图形（正方形 / 圆 / 等腰三角形）。
- [x] `payload.prompt` 改写为："这些图形沿哪条直线对折后能完全重合？这条直线叫什么？"
- [x] `script` 保留启发式提问，去掉「教师可上传」措辞。

**环节 3（探索）**
- [x] `payload.items[]` 引用 2 张 `platform_cc0` 图（对称点 A/A' 与轴 / 两图形各自标轴）。
- [x] `payload.prompt` 改写为："量一量 A 和 A' 到对称轴的距离，你发现了什么？"
- [x] 与 01 术语表对齐「对应点 / 距离相等」表述。

**验收**
- [x] 两个 media_gallery 环节不再含「教师可上传 / 教师可示例」占位字样。
- [x] 引用的素材在 `coursewareasset` 表存在且 `source=platform_cc0`：5 张图由 PIL 现场生成（CC0 1.0），落 `backend/data/materials/<CC0_OWNER>/`，注册为 `platform_cc0`，列表接口 `own | cc0` 对所有教师可见、`get_asset_file` 允许服务。
- [x] 演示端按 `asset_id` 命中素材、`Image.network(url)` 取 `/api/v1/courseware/assets/{id}/file` 渲染 5 张图与引导语。

**说明：** 图片为 PIL 绘制的内置教学示意图（非外部抓取，规避沙箱无外网）；如需更写实素材可后续经 T08 `seed_cc0.py` manifest 替换 `source_url`。
