# 02: 共享画廊加 play 角标，并支持保序渲染

**What to build:** 图形画廊的每张只读卡右上角出现一个 play 角标，提示"这张可以打开动手折"；并且当调用方传入一组**有序**图形时，卡片按传入顺序渲染，不再被库的默认顺序悄悄重排。

**Blocked by:** 01（持久化通路已确认不需要改后端）

**Status:** done

## A. 右上角 play 角标（可见性提示，不是唯一命中区）

- 卡片的 `Stack` 里右上角加 play 角标（lucide 的 play 图标，小尺寸），深块配白字语义，避免与左上角既有的「默认讲解」角标抢位。
- **保留 `AppFocusableAction` 整卡可点**——play 只是提示；只留小图标做命中区会显著削弱触屏可用性。且不额外套手势识别器：可点区全站只有 `AppFocusableAction` 一种语言（ADR-0046）。
- 语义标签同步改写（如"播放某图形的对折演示"），保住键盘可达性。
- 角标显隐做成可选参数，**默认显示**（全站统一），便于个别纯预览语境关闭。

## B. 保序渲染

- 现状的排序函数会把命中的选项排前面、其余按图形库顺序排——这会把教师编排的顺序悄悄重排。
- 新增可选参数（如 `preserveOrder`）：为 true 时直接按传入的图形列表顺序渲染，跳过排序函数。
- 画廊原本就接受图形列表参数且默认整库，**子集能力不用新建**。

## 验收

- [x] 卡片右上角出现 play 角标，与左上角「默认讲解」角标不重叠、不裁切。
- [x] 整卡仍可点，打开回调正常触发；键盘路径语义标签正确。
- [x] `preserveOrder: true` 时渲染顺序 == 传入顺序（**必须用逆序子集做断言**——正序子集在库序下也成立，测不出问题）。
- [x] 未传该参数时行为与今天完全一致（既有的选项组与场景库用例原样通过，仍是整库铺开 + 选项角标）。
- [x] 只读卡上**没有任何**"是否轴对称"的判定标记（本票也不许加）。
- [x] 为该画廊补 widget 测试 ≥2 例（角标存在 + 逆序保序）。注意：全站禁 Material 控件，测试须在**不套 Material 的树**里真构建；多列布局必须用 `setSurfaceSize` 设定表面尺寸，否则父约束会把尺寸夹回默认表面、误报溢出。
- [x] 静态检查该文件 0 issue。
- [x] ⚠️ 该文件现 329 行：加完若不慎超 400（ADR-0058），按既有先例**抽 part 文件**（如把 play 角标抽成独立 part），不得直接上调基线绕过。
  - [x] **未超限**：改完 375 行（+46），低于 400，无需抽 part、未动基线。

## Done note（2026-10-09）

### A. play 角标（`reflection_figure_gallery.dart`）

- 卡片 `Stack` 新增 `Positioned(top: 4, right: 4)` 的 18×18 深块角标（`AppBrutal.blue`
  + `AppBrutal.onDark` 白，发丝墨黑描边），内嵌 `Icon(LucideIcons.play, size: 11)`——
  lucide 图标、非 Material 控件；`show` 只导出 `LucideIcons`，不牵进 shadcn 其它符号。
- **不额外套手势识别器**：整卡命中区仍是唯一的 `AppFocusableAction`（ADR-0046），
  play 纯属可见性提示。
- `semanticLabel` 由「打开X的对折演示」改为「**播放**X的对折演示」，与角标视觉语义
  对齐；选中态（「当前讲解图形：X（点开重新演示）」）未动。
- 新增 `showPlayBadge`（默认 **true**，全站统一），纯预览语境可关。

### B. 保序渲染

- 新增 `preserveOrder`（默认 **false**）：为真时 `_ordered()` 直接返回 `figures`，
  跳过「选项置顶 + 库序」重排。子集能力复用既有的 `figures` 参数，未新建。
- 默认 false 是硬要求：题库 / 错题 / AI 讲解路径的观感必须一字不变。

### 证据（命令 → 结果）

```
cd frontend
no_proxy="127.0.0.1,localhost,::1" NO_PROXY="127.0.0.1,localhost,::1" \
  /Users/annilq/Documents/fulttersdk/flutter/bin/flutter test test/reflection_figure_gallery_test.dart
→ 00:00 +8: All tests passed!（新增 8 条）

同上跑 test/scene_option_group_test.dart test/scene_library_t04_test.dart test/file_size_guard_test.dart
→ 00:01 +19: All tests passed!（既有选项组 / 场景库 / 规模门禁原样通过）

同上全量 flutter test
→ 00:39 +418 ~1 -4：与集成分支 tip 上的 +410 ~1 -4 相比**只多 8 条通过**，失败仍是同样 4 条
   · no_bare_gesture_guard_test.dart（draggable_assistant_fab.dart:118 裸 GestureDetector）
   · courseware_editor_page_test.dart 3 条（编辑弹窗已无「选择讲解模板」文案，源于 aa23a29）

flutter analyze
→ 3 issues found，全部落在 analytics_screen_test.dart / scene_library_associate_dialog_test.dart
  （既有）；本票新增的 lib 与 test 文件 0 issue。
```

### 新增的测试（`frontend/test/reflection_figure_gallery_test.dart`，8 条）

挂载方式：`ShadApp.custom` + `CupertinoApp`（**不套 Material**）+ `setSurfaceSize(1200×900)`。

1. 每张只读卡右上角有 play 角标（默认显示）：`find.byIcon(LucideIcons.play)` 命中 3 个，
   且角标 `Positioned` 是 `right/top` 有值、`left` 为空（确在右上）。
2. play 角标与左上角「默认讲解」角标在同一张卡上共存且**矩形不相交**。
3. 整卡仍可点（点图形名触发 `onOpen`）+ 读屏标签含「播放X的对折演示」。
4. **逆序保序**：`figures = [一般四边形, 正方形, 房子]`（库序 10/4/0 的逆序），只给
   `house` 挂选项角标，`preserveOrder: true` → 卡片顺序 == 传入顺序。
5. 同一批数据**不传** `preserveOrder` → 房子被顶到第一位（与上条期望相反）。
   这条既钉住「默认行为一字不变」，也证明第 4 条的逆序断言有牙齿。
6. 不传任何新参数 → 整库铺开 11 张、选项角标在、带标号的排最前。
7. `showPlayBadge: false` → 无 play 图标，整卡照样可点。
8. 只读卡上无「轴对称 / 不对称」字样、`LucideIcons.check` / `.x` 均无（§2.5 只画不判）。

### 未做的事（本票纪律）

未改 `SceneInterpreter` 的 `curated` 分派（03 票）、未引入编辑器 UI（04 票）、未碰后端。
`preserveOrder` 目前还没有生产调用方——它由 03 票接上 `curated: true` 后启用，本票只把
能力钉在共享画廊里并用测试守住默认行为不变。
