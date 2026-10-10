# 图库 DB 化 + 画板设计 + SceneSpec 几何化 · Tickets 索引

> 来源：ADR-0083（读代码前先看它）。
> **[SPEC.md](SPEC.md)**：本轮可执行 spec（问题/方案/用户故事/实现与测试决策/非目标）。ticket 是垂直切片，冲突以 ADR-0083 为准。
> 本地 `.scratch`（gh 未认证，未建 GitHub issue）。每张 ticket 含 What to build / Blocked by / Status / 验收。

## 范围
把场景库几何从「代码常量 + 构建期 const + parity 双源锁」改为「DB 图库 + SceneSpec 自带几何 + 画板创作 + 视觉判定对称」。运行时渲染零图库依赖、零本地缓存。

## 依赖链

```
01 图库表 + 内置种子 + 读端点 ──────────（无前置）
02 SceneSpec 形态改造（后端产出+前端渲染）─ 01
03 旧 SceneSpec 向后兼容 + 回归 ───────── 02
04 画板 UI + 工具栏预设 + 保存端点 ───── 01, 02
05 画廊按需拉取（不缓存） ───────────── 01, 02
06 全链路回归与清理 ────────────────── 02, 03, 04, 05
```

## 分劈原则（to-tickets 拍板）
- **02 是跨层单切片**：SceneSpec 形状改造若拆成「后端 expand / 前端 switch」两票，合并窗口期后端出新版、前端仍读旧版会红；故作为一条垂直切片一次落地，保持 CI 绿。
- **04 不被 03 gate**：画板产出的是数据，用假仓库/端点断言保存内容即可自证，可与 03 并行。
- **05 与 04 平行**：同为图库消费者（写 vs 读），都只依赖 01+02，可并行。
- **06 收口**：退役 parity 锁与 `FIGURES` 常量，必须在所有改造票完成后。

## 用户决策锚点（grill-with-docs 钉死，勿再开讨论）

| # | 决策 | 出处 |
|---|---|---|
| 1 | 图库入 DB：`figure_library` 表存几何（points/edges），不再用代码 `FIGURES` + 构建期 const | 用户拍板 + ADR-0083 |
| 2 | 对称轴判定纯视觉（拖轴+翻转），不存任何 axis 属性；平行四边形等刻意不对称由用户自己看 | 用户拍板 |
| 3 | 特殊图形（square/triangle/parallelogram…）做成画板工具栏预设，点击即落画板 | 用户拍板 |
| 4 | `SCENE_LIBRARY` 保留作 kind 交互外壳（不同场景默认交互不同，如轴对称需对称轴） | 用户拍板 |
| 5 | `SceneInterpreter` 统一：画板=编辑态、播放=正常态，同一渲染器 | 用户拍板 |
| 6 | 去掉本地缓存：运行时渲染零图库依赖，图库仅创作 UI 按需拉取 | 用户拍板 |
| 7 | SceneSpec 精简为 `{kind, points, edges}`：删 inputs/controls/narrative/outputs/title/editable/`figure` 引用 | 用户拍板 |
| 8 | 轴初值（axisAngle/axisX/axisY）归 kind 外壳，不再每条 scene 各自存 | 用户拍板 |

## 共同纪律
- `flutter analyze` 0 issue；全仓 `flutter test` 无回归；单文件 ≤400 行（ADR-0058，超限抽 part，**不**直接上调基线）。
- 全站禁 Material 控件；可点区一律 `AppFocusableAction`。
- **题库 / 错题 / AI 讲解路径现有观感必须一字不变**（快照不可变，零回写 `kp.scenes`）。
- 旧形 `Question.scene_spec` 必须仍可渲染（03 适配层 + 快照不可变网守）。
