# 04: 课堂练习 practice 落地

**What to build:** 把课件 `cacb390…` 的环节 2（practice「练习补全对称轴」）从占位选项替换为 **2 道具体选择题**，每题含题干、4 个具体选项、正确答案、解析。

**Blocked by:** 01

**Status:** done

- [x] 题 1（补全图形）：题干"半圆形沿对称轴补全得到哪个图形？" → 选项[完整圆/半圆/扇形/椭圆]，答案 0，解析"两侧完全重合，半圆补成整体得完整的圆"。
- [x] 题 2（对称轴数量）：题干"长方形有几条对称轴？" → 选项[1/2/4/无数条]，答案 1，解析"长方形 2 条对称轴（对边中点连线，非 4 条）"。
- [x] `payload.hints` 改为具体提示（"对称轴是一条直线，两侧图形完全相同""先找已知一半，再沿对称轴对称画出另一半"）。
- [x] 选项文本去除「教师可示例图形（如…）」占位，改为确定的图形名/描述。
- [x] `qtype=choice`、`count=2` 保持不变；新增 `hint_level: direction` 默认（供渲染器分级提示透传）。

两题以 `payload.questions: [{stem, choices[4], answer_index, analysis}]` 结构化存储，与 01 大纲口径一致。

**验收**
- [x] 2 道题选项均为具体、互斥、有唯一正确答案；无「教师可示例」占位；解析存在且口径一致。

**⚠️ 渲染器行为（重要）：** 当前 `SectionPractice`（`section_practice.dart`）**不走 sections 里的静态题**——它点「出题」后调 `assistantNotifierProvider` 走 `POST /assistant/chat` 让 AI 实时生成题面，教师在本地点「对/错」并触发分级提示；`payload` 仅消费 `qtype` 与 `hint_level`。因此本 ticket 的 2 道具体题作为**教师编写的参考题 / 未来静态模式数据源**存入 `payload.questions`，直播练习环节的出题与判分仍由 AI 通道满足。要把静态题接入练习选择器（不再依赖 AI）需另开 ticket（建议挂 05 或单独 issue）。

**说明：** 沙箱无法跑 Flutter UI，未做真机出题验证；内容为数据与契约正确性。
