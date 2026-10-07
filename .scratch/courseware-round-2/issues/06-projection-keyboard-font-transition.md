# 06: 投影交互：键盘翻页 + 字号升档 + 轻过渡 + 安全区

Parent: docs/specs/teacher-courseware-round-2.md（ADR-0067 第二轮 · 投影方向）

**What to build:** 演示页能接翻页笔 / 键盘事件翻环节（右 / 下 / 空格 = 下一步，左 / 上 = 上一步），与现有按钮翻页并存；字号随可用宽度升档（守 `AppContentFrame` 的 `contentWide=1080` 居中列，不破坏首轮切片 8 的「不溢出」结论）；环节切换加轻过渡（尊重 reduced-motion）；横屏安全区按 `MediaQuery` padding 收边；全程复用首轮 `AppPushedPage` 全屏壳，不引入导航目的地、不破坏 ADR-0059 单源。

**Blocked by:** None（can start immediately）。

**Status:** done

- [x] 演示页监听键盘 / 翻页笔事件：右 / 下 / 空格 → 下一步，左 / 上 → 上一步；与底部按钮翻页等价并存。
- [x] 字号档随 `AppContentFrame` 可用宽度升档；步骤条与主区同步；升档不得破坏 1080 居中列约束（1920 与 1366 同档）。
- [x] 环节切换加轻过渡；`reduced-motion` 偏好下过渡不生效。
- [x] 横屏投影下按 `MediaQuery` padding 收安全区，四角信息完整。
- [x] 全程复用 `AppPushedPage` 全屏壳，无侧栏无底栏（ADR-0059 单源）。
- [x] 全程不引入 Material 系控件；`presentation/` 不 import `*/data/`。
- [x] 前端 widget 测试（关代理单进程）断言：键盘 / 翻页笔事件与按钮翻页等价；宽度升档后字号档变化；reduced-motion 下过渡不生效；1920×1080 / 1366×768 / 1024×768 三档不溢出。

**Done note (2026-10):** 演示页 `courseware_present_page.dart` 接 `KeyboardListener` +
`WidgetsBinding.instance.addPostFrameCallback` 自动聚焦；`fontScaleFor` 三档升档；`AnimatedSwitcher`
200ms 轻过渡并在 `reduced-motion` 下退化为 `Duration.zero`。`courseware_present_page_test.dart`
16 测试全绿（含 3 个 T06 新测试）；三件套 38 测试零回归；`flutter analyze lib/features/courseware`
0 issue。
