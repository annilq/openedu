# 新粗野视觉语言（撞色 + 硬描边 + 弹性动效）

替换 ADR-0004「设计约束 D」确立的 Linear 克制风（表面微暖白、卡片纯白 + 1px 极细描边、**无阴影**、中饱和学科色仅小面积）。新语言为**新粗野（Neo-Brutalism）**：高饱和原色撞色、2px 墨黑描边、无模糊硬阴影、弹性主导动效。本 ADR 是设计语言层，不动 ADR-0004 的层边界与令牌单一事实源约束。

## 决策

- **风格定为新粗野**：在八个候选方向（新粗野 / 儿童友好 / Material 3 表现力 / 几何扁平 / 黏土拟态 / 孟菲斯 / 杂志编辑 / 波普插画）中选定。选型依据不是审美，是唯一能在「双端统一强度」下保住家长端看板可读性的方案——层级由描边与位移承担，不依赖色块面积。
- **描边从 1px 升到 2px 墨黑，且是功能性必需而非装饰**（`frontend/lib/shared/theme/app_theme.dart:165` 的 `outline` 令牌语义改变）。实测相邻高饱和色块彼此对比度**中位数仅 1.67**，最低为 `violet/red = 1.00`（亮度完全相同）、`teal/orange = 1.03`、`yellow/lime = 1.07`；暖白纸底 `#FDFBF7` 上黄块仅 1.38、柠檬绿 1.47。无描边时色块边界在视觉上不存在。
- **「无阴影」约定作废，改用无模糊硬阴影**（solid offset，blur = 0）：常态 `Offset(3, 3)`，按压 `Offset(1, 1)`，按下时元素下沉 2px 模拟物理按压。禁用 `BoxShadow` 的 `blurRadius`（会破坏硬边语言）；Flutter 无内阴影 API，黏土式内阴影不在本方案内。
- **色块作强调件（emphasis block），不铺底**：双端统一到「家长端能承受的上限」。可执行上限——① 单卡片内彩色填充面积 ≤ 卡片面积 40%，其余为 paper/white；② 列表行禁止整行彩色填充，只允许左侧 4px 学科色条 + 学科 chip；③ 单屏内不同色相 ≤ 3；④ 仅 CTA 与选中态允许全填充。
- **双端统一强度，仅字号分档**：色彩饱和度、色块面积、圆角、动效强度两端一致，不引入 parent/child 双色板（用户明确要求减少抽象）。ADR-0014 的 Child Mode 字号放大一档**保留**（`_childScale`，`app_theme.dart:869`），低龄可读性为硬需求。
- **学科色三重编码**：色相 + 明度差 + **几何标记**，禁止仅靠颜色区分学科。数学 = blue `#2F6FD0` + ■；语文 = coral `#FF6B5A` + ●；英语 = yellow `#FFD43B` + ▲。语文/英语同属暖色系，在红绿色盲下趋同，由明度差（coral vs paper 2.71 / yellow vs paper 1.38）与几何标记兜底。
- **动效从三次贝塞尔升级为真弹簧**。`Curves.easeOutBack`（`app_theme.dart:1672`）是贝塞尔近似，多元素共用同一曲线时会「齐步走」，无质量差异。改用 `SpringDescription` + `SpringSimulation`（或 `springster` 包），给不同量级元素不同 damping/ratio：大卡片重、chip 轻。
- **`flutter_animate` 必须显式声明**：当前它在 `pubspec.lock:145` 存在但**未写入 `pubspec.yaml`**，经 `shadcn_ui` 传递引入，`app_theme.dart:1103` 已在用 `.animate().rotate()`。上游移除该依赖即构建失败。
- **`CupertinoApp` 根下 Hero 需手动注入**：`MaterialApp` 会自动挂 `HeroController`（含 `MaterialRectArcTween`），`CupertinoApp` 不会。跨页共享元素转场必须自建 `HeroController(createRectTween: (b, e) => RectTween(begin: b, end: e))`。
- **reduce-motion 覆盖隐式动画**：现有 `reducedMotionOf`（`app_motion.dart:14`，读 `MediaQuery.disableAnimations`）只保护 `PopIn` / `ConfettiBurst`。新增的 `AnimatedScale` / `AnimatedContainer` **不会自动尊重该设置**，必须显式写 `duration: reduced ? Duration.zero : ...`。

## 色板（全部经 WCAG AA 实测）

纸底 `paper #FDFBF7`、墨黑 `ink #111110`。每个色只有一种合规文字配对，不得互换：

| 令牌 | 值 | 文字 | 对比度 |
|---|---|---|---|
| yellow | `#FFD43B` | ink | 13.25 |
| lime | `#A9E34B` | ink | 12.39 |
| cyan | `#22B8CF` | ink | 7.94 |
| teal | `#12B886` | ink | 7.40 |
| orange | `#F08C00` | ink | 7.61 |
| coral | `#FF6B5A` | ink | 6.75 |
| magenta | `#E64980` | ink | 5.06 |
| green | `#2B9348` | ink | 4.83 |
| violet | `#7048E8` | white | 5.55 |
| red | `#C92525` | white | 5.56 |
| blue | `#2F6FD0` | white | 4.88 |

**推论（硬约束）**：所有高饱和色配**白字**均不达标（实测最高 4.78）。「亮块 + 墨黑字」是新粗野的签名组合，但它在此不是风格选择，是无障碍唯一解。深色档（violet / red / blue）配墨黑字不达标（3.40 / 3.40 / 3.87），**只允许配白字填充**。

## 动效令牌

保留 `AppMotion` 四档命名，曲线语义改为弹簧参数：

| 档 | 原曲线 | 新实现 |
|---|---|---|
| interaction 120ms | `Curves.easeOut` | 轻弹簧，按压下沉 2px |
| state 200ms | `Curves.easeOut` | 中弹簧 |
| page 300ms | `Curves.easeInOut` | 重弹簧 + 入场位移 |
| celebrate 450ms | `Curves.easeOutBack` | 保留，仅 Child Mode |

性能红线沿用：只动 transform + opacity；`ListView.builder` 中使用 `flutter_animate` 需给 item 稳定 key，否则复用时动画重放。

## 色相 ≤ 3 的适用口径（试点补充）

「单屏内不同色相 ≤ 3」约束的是**大面积色块**（> 卡片面积 5%）。以下不计入：

- 学科 chip / 题号 chip / 状态 pill——它们是**标识件**，色相由业务语义决定，面积 < 1%；
- 语义色容器（错误/警告/成功底）——仅在异常分支出现；
- 庆祝粒子（一次性、非持续视觉）。

试点首页实测：复习横幅 cyan（占横幅 28%）+ AI 横幅 yellow（28%）+ 任务卡 CTA 复用学科色 → 大块色相为 2，学科 chip 的蓝/珊瑚/黄不计入。

## 试点落地（2026-09-15）

token 层 + 两个试点页已完成，代码一行行改通，`flutter analyze lib` 零 issue。

**主题层（全站生效）**：
- `AppCard` → 2px 墨黑描边 + 硬阴影；可点击卡片按下时整块位移 `Offset(1,1)` 并收拢阴影。
- 按钮主题：实心 CTA 加 2px 墨黑边 + 硬阴影（浮起）；次级 / outline 按钮 2px 边但**无**阴影（平贴），避免表单里一排按钮全部浮起。
- `AppTags.subject` 改为**学科 accent 实心填充 + `AppBrutal.onColor` 前景 + 几何标记**，落地三重编码（数学■ 白字 / 语文● 墨黑字 / 英语▲ 墨黑字）。英语黄在纸底仅 1.38:1，故 chip 一律带 1.5px 墨黑描边。
- `SectionTitle` 左侧色条：3px 靛蓝 → 4px 墨黑。
- 新增 `AppBrutalButton`（任意撞色填充 + 合规前景 + 硬阴影 + 按压下沉）、`SubjectMarkIcon`（自绘实心几何形，不用 lucide 描边图标——9-12px 下描边糊成一团）。
- 彩带 `ConfettiBurst` 调色板换成撞色原色。

**试点一 · 儿童端首页**：两个 banner 改为「左侧撞色块（flex 2:5，约 28%）+ 右侧纸面」分栏，取消全填充；任务卡改为左侧 6px 学科色条 + 学科 chip + 学科色 CTA；空状态图标块改 yellow 实心方块；任务卡加 `PopIn` + `ValueKey(task.id)`（key 稳定才不会在刷新时重放动画）。

**试点二 · 家长端任务表单**：少题警示条改 `AppBrutal.red` 实心 + 白字；兴趣主题 chip 选中态改 cyan 实心 + 硬阴影；预览题卡 2px 边 + 硬阴影 + violet 题号 chip + 学科三重编码 chip；题卡加 `PopIn` + `ValueKey(index)` 实现逐张浮现；`_ThemeToggle` 的 `AnimatedContainer` 按 ADR 要求显式归零 reduce-motion 时长。

**待真机验证**：2px 墨黑描边 + 硬阴影加在家长端**密集列表**（掌握度看板 / 错题列表）上是否过吵——这是「统一到家长端上限」这一档唯一的风险点，只能眼睛说了算。

## Considered Options

① **两端分强度色板**（parent 降饱和 / child 全放开）——拒绝：用户明确要求减少抽象，两套 scale 会让主题层复杂度翻倍，且新增页面需声明归属哪一套。
② **黏土拟态 / 波普插画**——拒绝：Flutter 无内阴影 API 需自绘；波普依赖插画资产，团队无设计产出。
③ **孟菲斯 / 几何扁平**——拒绝：孟菲斯装饰元素长期疲劳且与错题本的严肃内容冲突；几何扁平零圆角在儿童端冷硬。
④ **取消双模式字号阶梯**——拒绝：低龄可读性是硬需求，且 `_childScale` + `UserModeScope` 已落地。
⑤ **保留 `Curves.easeOutBack`**——拒绝：单一曲线导致多元素齐步走，与「撞色大块」的层次诉求矛盾。

## Consequences

- ADR-0004「设计约束 D」的「1px 极细描边 / 无阴影」两条**被本 ADR 取代**，需在 0004 中交叉标注（本 ADR 不改 0004 正文）。
- `AppColors` 令牌集需扩充撞色档；`AppRadius` 从 6 收到 4（大面 0）；`ShadThemeData` 装配（`app_theme.dart:376`）需重配描边宽度与新增硬阴影装饰。
- 迁移路径：**token 层先行 + 试点**——先换 `AppColors` / `AppRadius` / `AppMotion` 与主题装配，再以儿童端首页 + 一个家长端页面（建议家长端任务表单）试点验证手感，跑通后铺开其余页面。禁止一次性全量重做。
- 主题自检页 `frontend/lib/dev/theme_preview.dart:857` 的「学科色仅作业务标识」校验需同步更新为新色板与三重编码规则。
- 新增页面不得硬编码色值；撞色填充必须走上表配对，否则在 `theme_preview` 自检暴露。
