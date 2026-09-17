---
name: design-token-consumption-audit
description: 审计 openedu 前端「已定义但没被消费」的设计令牌，定位设计语言未兑现的面板。当用户说「哪里平淡/静态/没颜色」「设计不一致」「新粗野迁移还剩哪些」「bolder/animate/colorize 打在哪个面」时使用。产出带 文件:行号 证据的 P0/P1/P2 排序清单，默认不改代码。
agent_created: true
---

# 设计令牌消费度审计（openedu 前端）

## 核心判据

**本仓的问题从来不是「不够响」，是「响得不均匀」——令牌层建完，消费层没跟上。**
所以「加码」不是再加效果，是把**已经设计好、却没人接**的效果接上。
审计的第一动作永远是：**找定义了但零调用的令牌**，而不是评价现有页面好不好看。

## 步骤

### 1. 建立规则源
先读 `.impeccable.md`（设计原则 1–8 + Accessibility + Empty State + Interaction）+ 相关 ADR。
**规则是判据的来源**——没有规则源，「改进建议」就只是个人品味，用户不会采纳。

### 2. 令牌消费矩阵（逐令牌 count）
对每个令牌跑一次 `Grep(output_mode: "count", path: "frontend/lib/features")`：

`AppBrutal` · `SubjectMark` · `AppElevation\.(borderWidth|borderWidthSm|borderWidthHairline)` ·
`PopIn|PressScale|ConfettiBurst` · `AnimatedContainer|AnimatedSwitcher|AnimatedOpacity|AnimatedAlign|AnimatedSize|TweenAnimationBuilder` ·
`AnimatedCrossFade|FadeTransition|SlideTransition|ScaleTransition|Hero\(|AnimatedList|AnimatedPositioned|CurvedAnimation` ·
`SectionTitle|AppTags\.|AppBadge\.` · `titleLarge|headlineSmall|headlineMedium|displaySmall|displayMedium` · `GestureDetector`

**读法**：
- 某令牌只在 `app_theme.dart` 内命中 → **疑似死令牌**（最高优先级发现）。用 `Grep(path: "frontend")` 复核。
  - ⚠️ **这一步极易误判，比看上去难**：令牌可能被 `app_theme.dart` 内部的**私有组件**消费，而那个私有组件
    是通过一个公开**工厂函数**（`AppTags.subject` / `AppBadge.*`）暴露的。只 grep 令牌名、只读工厂函数体，
    会得出「零调用」的**错误结论**，并连带把正确的业务注释判成「失实」。
    **正确做法：从工厂函数 `return` 的那个 widget 类进去，读它的 `build`。**（2026-09-17 就栽在
    `SubjectMarkIcon` 上：实际由 `_TagChip.build` 渲染，三重编码一直是通的。）
  - 复核结论必须**落到具体 widget 的 build**，不能停在「工厂里没有」。
- 命中文件数 / 业务文件总数（当前 136）→ 迁移进度。
- `GestureDetector` 命中后**必须 `-C 3` 看上下文**，确认是否裸（`PressScale` 与 `AppFocusableAction` 内部用它是合法的）。
  本仓大量**注释**在解释「为什么不用它」——`grep` 命中不等于违规，所以规则要交给**静态守卫**（见下），
  别靠人眼逐条读。

### 3. 交叉核对：注释失实
死令牌的高发伴生现象是**注释声称功能已生效**。对每个死令牌，搜它的中文/符号名（如 `■|●|▲`），
命中的如果全是注释 → 报告「注释失实」，这比没注释更坏。

### 4. 分类，不排序
- **P0 = 违反已写下的规则**（缺陷，不是审美）：死令牌 / 裸 `GestureDetector`(ADR-0046) /
  空态未走 `AppEmptyState`(ADR-0051) / 描边裸数字(ADR-0044) / 布局裸数字(ADR-0045)。
  P0 不需要用户做审美决策，可以直接进批次 A。
- **P1 = 设计语言未兑现**（该响没响）：类别色缺失、无焦点、字号阶差不足(<3×)、进度条无过渡。
- **P2 = 动效质量**（有但不合格）：入场无 stagger、折叠无高度过渡、等待态是纯文本。

### 5. 输出
写 `.scratch/design-amplification-audit-<YYYY-MM-DD>.md`（`.scratch/` 已存在且未跟踪，不污染仓库）。
每条必须带 **`文件:行号`** 证据 + **违反了哪条规则** + **具体提案**。结尾给「正面项（不要动）」
与「执行批次表（含前置依赖与验证手段）」。

## 常用命令

```bash
cd frontend
# 令牌消费分布（按命中数降序）
grep -rc 'AppBrutal' lib/features --include='*.dart' | sort -t: -k2 -nr
# 死令牌复核：只在 theme 内命中？
grep -rn 'SubjectMarkIcon' lib test
# 硬编码描边宽度
grep -rn 'Border.all(color: AppBrutal.ink, width: [0-9]' lib/features
# 裸 GestureDetector（必须看上下文）
grep -rn -C3 'GestureDetector' lib/features
```

## 从「清单」到「落地」（2026-09-17 A/B/C/D 四批次跑完的纪律）

- **每一条修复都要配一个会咬的守卫**，并**用反例探针验证它真的会红**（改坏 → 跑 → 看它失败 → 改回）。
  没验证过的守卫等于没有守卫：它可能因为 finder 写错、时机不对而恒绿。
- **静态扫得到的规则就静态扫**（`dart:io` 遍历 `lib/`，剥行注释后 `contains`）：`GestureDetector`、
  `disableAnimations`、手写 `Align+ConstrainedBox` 都走这条路。理由是这类违规**类型系统与 `flutter analyze`
  都看不见**，只有静态扫或人眼能发现。
- **分类陷阱**：`Semantics(button: true) + GestureDetector` **看着像合规**（有读屏语义），但**不进焦点树**——
  桌面端照样 Tab 不到。a11y 语义 ≠ 键盘可达，别把它算作已修复。
- **改令牌层（`app_theme.dart` / `app_motion.dart`）前问三个问题**：
  1. 这个隐式/显式动画在 reduce-motion 下怎么办？（`reducedMotionOf(context) ? Duration.zero : 令牌`）
  2. 新增的判据/常量放哪？**放 `app_theme.dart`**——`shared/widgets/` 反向 import 会成 theme↔widgets 循环
     （`AppFocusableAction` 留在 `app_theme.dart` 就是同一原因）。**不要为了「不改调用点」而用
     `export ... show X` 转出**：那会让调用点的原 import 全变 `unnecessary_import`，而本仓要求 analyze 零 issue。
  3. 首帧要不要动？隐式动画若要「首帧不进场地落在终值」，用 `TweenAnimationBuilder(begin == end == target)`
     （`initState` 里 `begin == end` 不会 `forward()`）。
- **透镜落不下去时，明说落不下去**，不要为了交差去动令牌（如 bolder 要 3–5× 字号阶差，而 `AppText._typeScale`
  上限 22px / 下限 12px → 物理最大 1.83×，要 3× 得新增令牌 + 一个 ADR）。改为「用别的手段制造焦点」
  （一屏只有一张彩色卡），并把限制写进交付说明。

## 已知结论（2026-09-17 审计 + 同日 A/B/C/D 落地，重跑时先比对是否已修）

- ~~`SubjectMarkIcon` / `SubjectKey.mark` 零业务调用~~ **❌ 此结论是错的**（见上「读法」）：实际由
  `app_theme.dart` 的 `_TagChip.build` 渲染（`AppTags.subject` 返回它）。三重编码的形状层是通的。
  `practice_question_view.dart:49,90` / `child_home.dart:391` 的注释**也是对的**，不是失实注释。
  真缺口只有 `mastery_board.dart:159-164` 的纯色点 → **已改 `SubjectMarkIcon`**。
- `assistant_cards.dart` 内 `AppBrutal` 零命中 → **已修**：`_CardHeader` 接类别色
  （cyan=待办/复习、magenta=错题/掌握、其余中性），前景 `AppBrutal.onColor`。
- 裸 `GestureDetector` **实为 7 处**（清单曾漏 `child_home.dart:223` 的 `Semantics+GestureDetector`）→ **已全部修**，
  守卫 `test/no_bare_gesture_guard_test.dart`。
- 手写空态 **实为 3 处**（曾漏 `parent_tutor_logs_view.dart`）→ **已全部走 `AppEmptyState.inline`**。
- `AppProgressBar` 无填充过渡 → **已修**（`TweenAnimationBuilder` + reduce-motion 分支），
  守卫 `test/progress_bar_transition_test.dart`（双向值变化）。
- `PopIn` 无 `delay` → **已修**，守卫 `test/pop_in_stagger_test.dart`。
- 流式等待态纯文本 → **部分修**：阶段文案走 `AnimatedSwitcher`（key 必须绑文本），
  守卫 `test/assistant_stage_switch_test.dart`。**脉动未做**（气泡里已有不确定态 spinner）。
- 待办（下一轮）：`AppCurves` / `AppMotion` / `AppSprings` 三套语汇的消费点清点（应落 ADR 或 issue）；
  P1-1/P1-3 除助手卡片与家长概览外的全站铺开。

## 纪律

- **默认不改代码**。用户要的是清单时，就只给清单。
- 提案必须守既有约束，别把审计做成「再加效果」：色块 ≤ 卡片 40%、**单屏色相 ≤ 3**、
  列表行禁整行填充、描边禁裸数字、任何新增隐式动画必须显式处理 reduce-motion。
- 建议「单屏色相 ≤ 3」的落地方式：**按语义族归并**（如 待办/复习 一族、错题/掌握 一族、结构类保持中性），
  **不要一种卡片一个色**。
- ⚠️ 改 `app_theme.dart` 前先 `git status` + 看 mtime（多会话并行，该文件被并发整写覆盖过）。
