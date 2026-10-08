# 03: 场景解释器支持 curated 子集分派（三态）

**What to build:** 一份环节场景数据交到场景解释器手里，解释器能按数据自己决定怎么摆：没有图形组 → 走今天的单场景路径；有图形组且声明为「教师编排」→ 按条目顺序只渲染指定的那几张；有图形组但未声明 → 仍是整库铺开。

**Blocked by:** 02（需要画廊的保序渲染能力）

**Status:** done

## 为什么必须是显式开关

场景选项组现在是「整库铺开让儿童自由探索」，这是**刻意**的产品决策。而题库/错题路径的条目恰好也非空（它们就是选项），**无法靠条目有无**区分"该整库"还是"该裁剪"。一旦按条目裁剪，等于静默剥夺学生探索其余图形的能力。故必须显式声明 `curated`。

## 要做

1. 解释器从场景数据里就地读取 `curated`（布尔，缺省 false），传给选项组组件；**不给解释器加构造参数**——它被多处调用，加参会波及全部消费方。
2. 选项组组件新增可选 `curated` 参数：
   - `true`：由条目**按其数组顺序**解析出图形列表（复用现有的 caption→图形、顶点比对逻辑），交给画廊并置上保序（ticket 02 提供）；
   - `false`（缺省）：**完全保持今天的行为**——整库图形 + 选项角标 + 库序。
3. `curated: true` 时不传选项角标（课件语境没有 A/B/C），避免出现无意义的空角标。
4. 弹窗打开某张图时的初始轴取**该图形自带的默认轴**，不套用环节场景配置的轴——否则唯一对称轴是横向的图形一打开就停在竖轴上，看着像"题目错了"。

## Done note（2026-10-09）

### 改了什么（`frontend/lib/shared/widgets/scene_interpreter/scene_interpreter.dart`，198 → 237 行）

- `SceneInterpreter.build` 就地读 `optionGroup['curated'] == true` 并往下传；**对外
  构造签名一字未动**（diff 里无参数增删），出题解析卡 / 错题本 / AI 讲解三处消费方
  零改动。
- `SceneOptionGroup` 新增可选 `curated`（默认 **false**）：
  - `true` → 由条目**按数组顺序**解析出 `List<FigureShape>` 交给画廊
    （`figures`）+ `preserveOrder: true`（02 票已有能力，未重复造）+ **不传
    `optionLabels`**（课件语境没有 A/B/C）；
  - `false` → `figures: kFigureShapes` + 角标 + 库序置顶，逐字段与今天一致。
- `_matchFigures()` 的返回从 `Map`（丢序）换成有序 `List<_MatchedFigure>`；整库
  路径的「同 key 只取首个条目」语义用 `seen` 集合保住（`putIfAbsent` 等价）。
- 初始轴沿用既有口径 `figure.defaultAxisAngle`（ADR-0076 §2.6），两条路径一致。
- 条目含库外图形 → 跳过、不留空卡；curated 且**全部**匹配不到 → 回落既有的
  `AppEmptyState`（而不是渲染一个零卡的空网格）。

### 证据（命令 → 结果）

```
cd frontend
no_proxy="127.0.0.1,localhost,::1" NO_PROXY="127.0.0.1,localhost,::1" \
  /Users/annilq/Documents/fulttersdk/flutter/bin/flutter test test/scene_interpreter_curated_test.dart
→ 00:00 +9: All tests passed!（新增 9 条；实现前先跑为 -3，红→绿）

同上跑 test/scene_option_group_test.dart test/reflection_figure_gallery_test.dart test/file_size_guard_test.dart
→ 00:00 +20: All tests passed!（既有选项组 / 画廊 / 规模门禁原样通过）

同上全量 flutter test
→ 00:34 +427 ~1 -4：与集成分支 tip 相比**只多 9 条通过**，失败仍是同样 4 条
   · no_bare_gesture_guard_test.dart（draggable_assistant_fab.dart:118 裸 GestureDetector）
   · courseware_editor_page_test.dart 3 条（编辑弹窗已无「选择讲解模板」文案，源于 aa23a29）
   （已用 git stash 撤掉本票改动单独跑这两个文件复核：同样 4 条失败，与本票无关）

flutter analyze
→ 3 issues found，全部落在 analytics_screen_test.dart / scene_library_associate_dialog_test.dart
  （既有）；本票改动的 lib 与新增的 test 文件 0 issue。
```

### 新增的测试（`frontend/test/scene_interpreter_curated_test.dart`，9 条）

挂载：`ShadApp.custom` + `CupertinoApp`（**不套 Material**）+ `setSurfaceSize`；
单场景用例用 420×1000、画廊用例用 1200×900。

| # | 断言 |
|---|---|
| 1 | 无 `optionGroup` → 单场景（`SceneOptionGroup` / 画廊均无，`ReflectionSceneWidget` 1 个） |
| 2 | 无 `optionGroup` 时可交互仍由 `editable` 决定：`false` → 1 个滑块、`true` → 4 个（3 轴 + 1 进度） |
| 3 | `curated: true` + 3 条目 → 只 3 张卡，顺序 == 条目顺序（**逆库序** 正方形 4 → 箭头 2 → 房子 0） |
| 4 | `curated: true` → 不渲染选项角标（条目**故意**带 A/B/C，仍一个都不出现） |
| 5 | 有 `optionGroup` 无 `curated` → 整库 11 张 + A/B 角标 + 房子置顶（与第 3 条期望相反） |
| 6 | curated 含库外图形（caption `外星图形` + 3 个不在库内的点）→ 跳过，剩 2 张且不空卡、无异常 |
| 7 | curated 点**箭头** → 弹窗初始轴 **0°**（环节配的是 90°，横向图形一打开就是横轴） |
| 8 | curated 点**正方形** → 初始轴 90°，弹窗内 4 个 `AppSlider`（3 轴 + 1 进度 = 可旋转 / 平移） |
| 9 | curated 只读卡上无「轴对称 / 不对称」字样，`LucideIcons.check` / `.x` 均无（§2.5 只画不判） |

### 未做的事（本票纪律）

未动编辑器勾选 UI（04 票）、未碰后端（01 票已核实零改动）、未改讲课页环节组件
（`section_interactive_scene.dart` diff 为空）。`curated` 目前还没有生产供给方——
由 04 票在课件编辑器里写入 `optionGroup.curated = true` 后启用，本票只把分派通路
钉在解释器里并用三态测试守住题库路径一字不变。

## 验收（输出侧主接缝：喂一份场景 dict，断言渲染出来的东西）

- [x] **三态逐一定在 widget 测试里**：无图形组 → 单场景；`curated: true` 且 3 个条目 → 只渲染 3 张卡且顺序与条目一致（用非库序条目断言）；有图形组但无 `curated` → 整库网格。
- [x] 缺省路径**逐字段与今天一致**（既有选项组用例全绿：整库数量不变、选项角标仍在）。
- [x] 条目里出现库外图形（匹配不到）时优雅跳过，不崩、不留空卡。
- [x] 点任意卡 → 弹窗内可旋转 / 平移对称轴，且初始轴 == 该图形自带默认轴（横向图形须一开始就是横轴）。
- [x] 只读卡上**没有**任何"是否对称"的判定标记。
- [x] 解释器对外构造签名**未变**（diff 里无参数增删：`SceneInterpreter({key, kind, spec})` 一字未动）。
- [x] 静态检查该文件 0 issue（`flutter analyze` 的 3 条全部落在既有测试文件）。
