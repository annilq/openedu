# 02: 前端垂直切片 — clarify 引导卡与汇总展示

**What to build:** 聊天 UI 在消息流里识别澄清消息（`extra.clarify`），渲染结构化引导输入卡：枚举槽按 `enum` / `enum_ref` 出可点选选项，int 槽出数值输入，文本槽出输入框；用户补参后回填并发送，下一轮进入生成（与 01 的跨轮合并协同）。同时渲染「已确认规格」汇总帧，列出被默认填充的项（如"知识点：未指定""难度：medium"）。复用现有消息流，不新增帧类型。

**Blocked by:** 01（契约稳定：`extra.clarify` 形状与汇总帧）

**Status:** done（已合入 `integration/tool-input-schema-slot-filling`）

> 实现补记：无 Material 控件（可点区走 `AppFocusableAction`、输入用 `CupertinoTextField`）；
> 年级 chip 回传「3年级」而非「3」，因后端按「N年级」正则抽取。历史回放
> （`AssistantMessage.fromBubble`）暂不还原引导卡——气泡载荷未带 clarify，属后续增强。

- [x] 识别 `AssistantMessage.extra.clarify` 非空 → 走引导输入卡分支（否则普通气泡）。
- [x] 枚举槽按 `enum` 直接用、`enum_ref` 映射到前端既有学科常量（与 `app.domain.subjects.SUBJECTS` 同源）；int 槽数值输入；文本槽文本输入。
- [x] 点选 / 输入补参后回填并发送；下一轮与 01 跨轮合并协同、进入生成。
- [x] 汇总帧展示已填 + 默认填充项清单，提供「修改」入口。
- [x] `flutter analyze` 0 issue；几何 / 结构断言通过（禁截图装置）；前端测试无回归。

## 纪律 / 实施提示
- 全站禁 Material 控件；可点区一律 `AppFocusableAction`。
- 单文件 ≤400 行（ADR-0058，超限抽 part，不直上调基线）。
- 前端测试禁截图装置（无合成器会挂死）→ 一律几何 / 结构断言。
- 复用现有消息流组件，不改 `AssistantEvent` 类型（业务字段走 `extra`）。
