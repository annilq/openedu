# 设计加码诊断清单（bolder / animate / colorize 三透镜）

> 日期：2026-09-17 · 范围：`frontend/lib` 全量（跨 feature）
> 判据来源：`.impeccable.md`（设计原则 1–8 / Accessibility）、ADR-0044、ADR-0045、ADR-0046、ADR-0051
> 方法：令牌消费度量化（`AppBrutal`/`SubjectMark`/`AppElevation`/`AppSprings`/`PopIn`/`PressScale` 逐文件计数）+ 关键文件精读
>
> ⚠️ **诊断部分的结论已经被执行过程推翻过三处**（P0-1 的「零业务调用」、P0-2 的「六处」、P0-3 的「两处」）。
> 各节标题处已就地标注更正，**以文末「落地结果」与「与本文诊断的两处出入」为准**。
> 保留被推翻的原文是为了留下「这一版为什么读错了」的线索——删掉它，下一次还会用同一种读法读错。

---

## 一句话结论

**问题不是「不够响」，是「响得不均匀」——令牌层已经建完，消费层没跟上。**

`app_theme.dart` 里 `AppBrutal`（11 个撞色 + `onColor()` 合规配对）、`SubjectMarkIcon`、`AppElevation`（三档描边 + 硬阴影）、`AppSprings`（四档物理弹簧）、`AppProgressBar` 全部齐备且注释详尽。但 136 个业务文件里**只有 23 个**消费了新令牌，而且两条**语义色通道完全没接上**：

| 通道 | 令牌 | 业务层调用次数 |
|---|---|---|
| 学科几何形状编码 | `SubjectMarkIcon` / `SubjectKey.mark` | **0** ← ❌ **读错了，见 §P0-1 更正** |
| 卡片类别色（9 种助手卡片） | `AppBrutal` | **0**（`assistant_cards.dart` 内）← 确认属实，已修 |

所以本轮加码不是「再加效果」，而是**把已经设计好、却没人接的效果接上**。这决定了 P0 全部是**缺陷修复**（违反已写下的规则），P1/P2 才是审美加码。

---

## P0 · 违反既有硬规则（不是审美问题，是缺陷）

### P0-1 学科几何标记层是死代码，三重编码实际只有「颜色」一重 ❌ **本节结论作废**

> **更正（执行时发现）**：本节的核心断言是错的。`SubjectMarkIcon` 并非零业务调用——
> `AppTags.subject` 返回的私有组件 `_TagChip`，其 `build` 里就渲染了
> `SubjectMarkIcon(mark: subject!.mark, color: fg, size: 9)`（`app_theme.dart:2086`）。
> **形状层一直是通的**，下面列的 3 条「失实注释」也是对的。
> 我的推断漏洞：只读了工厂函数 `AppTags.subject`，没有读它返回的那个私有组件内部。
> 本节唯一成立的部分是最后的「最该用它的位置反而手搓了色点」——`mastery_board.dart`
> 那处已改 `SubjectMarkIcon`。详见文末「与本文诊断的两处出入」第 1 条。

**证据**
- `app_theme.dart:131`（`enum SubjectMark`）、`:134-141`（`SubjectKey.mark` 映射）、`:147-164`（`SubjectMarkIcon` 自绘实心标记）、`:166-196`（`_SubjectMarkPainter` 画 ■ ● ▲）——**全仓仅在这些定义处出现，零业务调用**。
- `AppTags.subject`（`app_theme.dart:2049-2056`）只传 `subject: key` 着色，`icon` 参数默认 `null`，**不渲染形状**。
- 三处注释**声称**三重编码已生效，与实现不符：
  - `practice_question_view.dart:49`「学科色条：左侧撞色块 + 学科 chip 三重编码（math■ / chinese● / english▲）」
  - `practice_question_view.dart:90`「chip 自带色 + 几何标记」
  - `child_home.dart:391`「学科 chip 自带色 + 几何标记（数学■ / 语文● / 英语▲）」
- 最该用它的位置反而手搓了色点：`mastery_board.dart:159-164` 是 10×10 `borderRadius: 3` 的纯色块，**只编码色相与明度，不编码形状**。

**违反** `.impeccable.md` §Design Principles 4「学科永不只靠颜色。色相 + 明度差 + 几何标记三重编码……红绿色盲是真实用户」。

**为什么是真缺陷而不是洁癖**：`SubjectColors`（`app_theme.dart:54-70`）里语文 = `#FF6B5A`（coral）、英语 = `#FFD43B`（yellow），同在暖色系且明度接近。红绿色盲用户看到的是两个几乎一样的暖色块——`.impeccable.md` 自己写明了这个场景，形状层就是为了兜底它。

**提案**
1. `AppTags.subject` 默认渲染 `SubjectMarkIcon(mark: key.mark, size: 10)` 作为 leading（`AppTags.subject` 已有 `icon` 参数位，接口不用改）。
2. `mastery_board.dart:159-164` 的色点换成 `SubjectMarkIcon`——这是形状码**收益最高**的单点，因为同一行里同时有色点和按学科着色的进度条（`:204-209`），两条颜色通道、零形状通道。
3. 修正上述 3 处失实注释（注释说有的东西没有，比没注释更坏）。
4. 加守卫：学科 chip 必含一个 `SubjectMarkIcon`（放 `frontend/test/`，与既有 `app_focusable_keyboard_test.dart` 同风格）。

---

### P0-2 六处裸 `GestureDetector`，不在焦点树里 ⚠️ **实为 7 处**

> **更正**：漏了 `child_home.dart:223` 的 `Semantics(button: true) + GestureDetector`——
> 它**有读屏语义但同样不进焦点树**（a11y 语义 ≠ 键盘可达），静态扫才浮出来。
> 7 处已全部收口。

**证据**（`AppFocusableAction` 未出现于这些位置的祖先链）

| 文件:行 | 交互 |
|---|---|
| `assistant_cards.dart:451` | 推理折叠面板头（展开/收起） |
| `assistant_message_list.dart:248` | 点击复制消息 |
| `parent_question_bank_view.dart:351` | 选择题目（`Navigator.pop(t.id)`） |
| `parent_question_bank_view.dart:729` | 「用过 N 次」标签 → 弹引用列表 |
| `interest_picker.dart:199` | 兴趣选择瓦片 |
| `parent_task_form_view.dart:625` | 任务表单选择瓦片 |

**违反** ADR-0046 / `.impeccable.md` §Design Principles 8：「裸 `GestureDetector` 是 bug——Tab 跳不过去、Enter 点不动，而 `flutter analyze` 照不出来」。

**注**：后两处（`interest_picker` / `parent_task_form_view`）的 `build()` 根节点就是 `GestureDetector`，调用点**可能**已包外层；但即便如此，把可达性推给调用方本身就是脆弱设计。前四处是明确的违规——尤其 `assistant_message_list.dart:248`，同文件 `:246-247` 的注释还专门解释了「为什么不用 InkWell」，却顺手落进了另一个坑。

**提案**：换 `AppFocusableAction`（已定义在 `app_theme.dart:1478`，带 `hoverHighlight`）。`floating_assistant.dart:52-54` 有一段注释记录了同一类修复的历史（「原先是一个裸 GestureDetector——不在焦点树里……现在走 AppFocusableAction」），可以照抄那个改法。

---

### P0-3 空态三套画法并存，同一个文件里就不一致 ⚠️ **手搓版实为 3 处**

> **更正**：漏了 `parent_tutor_logs_view.dart:70-92`（cyan 底 + 2px 描边，又是一种画法）。
> 三处手搓版（`mastery_board` 无描边 / `parent_overview` 黄底 / `parent_tutor_logs` cyan 底）
> 的撞色、描边、色块尺寸互不相同，已全部收敛到 `AppEmptyState.inline`。

**证据**
- `mastery_board.dart:30-78`：手搓 `AppCard` + 52×52 色块（`scheme.tertiaryContainer`，**无描边**）+ 文案
- `parent_overview_view.dart:75-100`：手搓 `AppCard` + 52×52 色块（`AppBrutal.yellow`，**有 2px 描边**）+ 文案
- `parent_overview_view.dart:174`：走 `AppEmptyState.inline` ✓

**违反** ADR-0051 与 `.impeccable.md` §Empty State：「统一走 `AppEmptyState`……三态共用同一骨架（88 色块 / 标题 / 说明 / 行动）」。

同文件里两种画法、色块尺寸又都与规范里的 88 不同，且两个手搓版的描边处理还相反（一个有边一个没边）——这正是 `.impeccable.md` 记的「白物体在纸底没边界」陷阱，`mastery_board` 那版已经踩了。

**提案**：两处手搓收敛到 `AppEmptyState.inline`（该栏只有约一屏四分之一，`parent_overview_view.dart:168-170` 的注释已经论证过为什么该用 inline）。

---

### P0-4 描边裸数字四处

**证据**：`parent_tutor_logs_view.dart:81`（`width: 2`）、`parent_overview_view.dart:88`（`width: 2`）、`parent_overview_view.dart:318`（`width: 1.5`）、`parent_question_card.dart:143`（`width: 2`）。

**违反** ADR-0044 描边三档 + `AppElevation:265-271` 的注释（该注释专门记录了「仓里原先散着 6 处字面量 `1`」的教训——看来清掉了 `1` 档，`2` / `1.5` 档还留着）。

**提案**：换 `AppElevation.borderWidth` / `borderWidthSm`。注意 `parent_overview_view.dart:318` 的 `1.5` 是「36×36 图标底座」——按 `AppElevation:268` 的口径它归 `borderWidthSm`，取值恰好一致，属**语义**修正。

> **执行结果**：4 处里只有 `parent_question_card.dart:143`（题号徽标）需要真的改令牌 →
> `borderWidthSm`。另外 3 处（`parent_tutor_logs_view:81`、`parent_overview_view:88`、
> `parent_overview_view:318`）**随空态迁移（P0-3）与 `_StatCard` 整体删除（批次 B）一起消失**——
> 这也是为什么最后只落了 1 处令牌替换，不是漏做。

---

## P1 · 设计语言未兑现（该响没响）

### P1-1 AI 助手卡片层：9 种卡片、零撞色、零类别色

**证据**
- `assistant_cards.dart:86-92`：所有卡片统一走 `AppCard`（白底 + 2px 墨黑描边 + 硬阴影）——**9 种卡片是 9 张一模一样的白板**。
- `assistant_cards.dart:114`：卡头图标 `size: 15, color: scheme.onSurfaceVariant`——**全部中性灰**。
- `:619-627`：每种 kind 确实映射了不同图标（`listChecks`/`bookOpen`/`calendarClock`/`target`/`user`/`barChart3`/`library`），但都渲染成同样的 15px 灰——**图标差异在 15px 灰色下几乎不可辨**。
- `:146` `_ListCard` 一个版式承担 5 种列表卡（`taskList` / `wrongQuestionList` / `dueReviewList` / `masteryList` / `childList` / `questionBankList`）。
- `AppBrutal` 在整个 `assistant_cards.dart` 内 **0 次命中**；全 `features/assistant/` 只有 `floating_assistant.dart`(1) 与 `assistant_hint_card.dart`(3)。**唯一有色彩的卡片元素是题卡的学科色条**（`:316-319`）。

**为什么这条 ROI 最高**：AI 助手是仍在迭代的功能（ADR-0047/0048），卡片是它的主要产出物；会话回放（ADR-0048「点开只读回放」）里同一屏会连续出现多种卡片——用户此刻**分不出**「这是到期复习列表还是错题列表」。

**提案**（colorize 透镜，务必守 `.impeccable.md` 原则 2「单屏色相 ≤ 3」）
- 给卡头图标做一个 36×36 撞色底座 + 1.5px 墨黑描边，规格直接复用 `parent_overview_view.dart:312-322` 的 `_StatCard`（已是既有语言，不新增词汇）。
- 前景一律 `AppBrutal.onColor(fill)`，**不要**手写黑/白（`app_theme.dart:202` 明令）。
- 「单屏色相 ≤ 3」的落地方式：不要 9 种各一色。按**语义族**归并成 3 组——**待办/复习类**（taskList / dueReviewList）一色、**错题/掌握类**（wrongQuestionList / masteryList / questionBankList）一色、**结构类**（childList / progress / notice）保持中性。这样单屏最多 2 撞色 + 中性。
- 试点建议：只做 `question` + `dueReviewList` + `wrongQuestionList` 三种（最高频），跑通再扩。

---

### P1-2 家长概览 4 张指标卡：3 张中性灰，且无主次

**证据**：`parent_overview_view.dart:298-303` 的 `_Tone` 映射——`positive` → `tertiaryContainer`、`warm` → `secondaryContainer`、`alert` → `errorContainer`、**`neutral` → `surfaceSunken`**。而 `:123-144` 的调用里 4 张卡有 2 张用 `neutral`（总题数、答对），只有正确率（`positive`）和连续打卡（`warm`）有语义色。4 张卡 `cardWidth` 完全相同、字号相同 → **没有焦点**。

**违反** bolder 透镜的核心要求（「Focal point: 什么应该是 hero moment？Pick ONE, make it amazing」）与 `frontend-design` 的「DON'T: Use identical card grids」；也违背 `.impeccable.md` 家长端情绪目标「一眼看清、有掌控感」。

**提案**：选**一张**当焦点。建议「连续打卡」——它是唯一带情绪钩子的指标（对孩子是游戏化，对家长是动力）。给 `AppBrutal` 撞色底（亮块配 `AppBrutal.ink`）+ 字号上一档 + 面积占 2 个网格位；其余三张降为安静行（去卡片壳、只留图标 + 数字 + 标签），把重量让给焦点。

---

### P1-3 字号缺少页级「大字」档，阶差普遍不到 1.5×

**证据**：`titleLarge|headlineSmall|headlineMedium|headlineLarge|displaySmall|displayMedium` 在 `features/` 只有 **7 个文件 8 处**命中。全站最高档出现在 `_StatCard`（`parent_overview_view.dart:325` `headlineMedium`）与 `login_screen.dart`。

**违反** bolder 透镜「Extreme scale: 3x-5x differences, not 1.5x」——`_StatCard` 的 `headlineMedium` vs 其标签 `bodySmall`（`:330`）是**全站最大的阶差**，也才约 2×。页面级完全没有 display 档，所以每个页面都没有「第一眼看哪里」的答案。

**提案**：给页面的**唯一**核心数字上 `display*` 档，与正文形成 3× 以上阶差。落点建议：家长概览的焦点指标（与 P1-2 合并成同一件事做）、`practice_done_view`（42 行，练习题结页，天然该有一个大字得分）、`review_empty_view`。**一页只许一个**，否则等于没有。

---

### P1-4 `AppProgressBar` 无填充动画，进度条直接跳到终值 ✅ 已落地（批次 D）

**证据**：`app_theme.dart:1918-1927` —— `AppProgressBar` 是**裸的 `ShadProgress`**，`value` 直传，无任何过渡。调用点如 `mastery_board.dart:204-209`（掌握度条，`height: 10`）在数据到达的瞬间定值。

**违反** animate 透镜「State Transitions → Loading states / 进度指示」——进度条是**最该有动效**的控件之一，因为它表达的正是「变化量」。

**提案**：在 `AppProgressBar` 内部加填充过渡（`TweenAnimationBuilder<double>` 或 `AnimatedFractionallySizedBox`），并**显式**处理 reduce-motion（`app_theme.dart:2652-2653` 的注释已预警：隐式动画不会自动尊重系统设置）。改令牌层会动到全站，需配守卫测试——可参照 `test/control_height_test.dart` 的「守实测值」风格。

---

## P2 · 动效质量（有，但不合格）

### P2-1 `PopIn` 没有 `delay` 参数 → 列表入场只能「齐步走」

**证据**：`app_motion.dart:27-43`，`PopIn` 的参数只有 `child` / `fromScale` / `spring`，**没有 delay**。而 `parent_overview_view.dart:189-205` 给「最近任务」的**每一行**都套了 `PopIn`（`:192`）→ 4 行同时弹出。

**这是设计原则的自相矛盾**：`app_motion.dart:12-13` 与 `.impeccable.md` 原则 5 花了大段论证「为什么用物理弹簧取代 `Curves.easeOutBack`」——理由是「所有元素共用同一条曲线，多元素同时动时会『齐步走』，没有质量差异」。但入场**没有 stagger**，同一时刻起跳的元素照样齐步走；弹簧只解决了曲线差异，没解决时间差异。

**提案**：`PopIn` 加 `delay`（`Timer`/`Future.delayed` 触发 `_controller.animateWith`，注意 `dispose` 要能取消），或新增 `StaggeredList` 封装；步进 40-60ms（animate 透镜给的是 50-100ms，本仓手势较快，取偏小值）。

### P2-2 推理折叠面板无过渡，chevron 瞬时换图标

**证据**：`assistant_cards.dart:451-463` —— `GestureDetector(onTap: () => setState(() => _open = !_open))`，`:463` 是 `_open ? LucideIcons.chevronUp : LucideIcons.chevronDown`，**图标硬切、内容无高度过渡**。

**提案**：chevron 换 `AnimatedRotation`（`turns: _open ? 0.5 : 0`，200ms，`AppCurves.state`），内容换 `AnimatedSize` 或 `AnimatedCrossFade`。两处都要包 reduce-motion 归零。

### P2-3 流式等待态是纯文本

**证据**：`assistant_message_list.dart:187` —— `message.stage.isEmpty ? '思考中…' : message.stage`，就是一行字。整个 `features/assistant/` 里 `Animated`/`Curve`/`Duration(` 合计只有 **4 处**命中，且集中在 `assistant_message_list.dart`(1)。

**为什么值得做**：流式是 AI 产品**最长的一段等待**，纯文本让应用显得卡住。这也是 animate 透镜里「Feedback layer」的典型场景。

**提案**：等待时给气泡加脉动（`Opacity` 呼吸）或三点跳动；`stage` 文案切换走 `AnimatedSwitcher`（`AppCurves.state`）。注意 `.impeccable.md` §Aesthetic Direction 的「不用柔和阴影讨好」——脉动要**硬**（离散跳变或 `Transform.scale` 阶跃），不要渐隐渐现的柔光。

### P2-4 三套动效语汇并存

**证据**：`AppSprings`（`app_theme.dart:300`，物理弹簧）、`AppMotion`（`:2621`，Duration 四档）、`AppCurves`（`:2654`，Curve 四档）。`AppCurves:2643-2653` 的注释已自我降级为「必须是 Curve 的场合专用」，但业务层仍在消费它。

**提案**：不是立刻删除——先做一次消费点清点，把「其实可以用弹簧」的场合标记出来。这是**技术债登记**，不是本轮改动。建议写成 ADR 或 issue，避免下次又踩。

---

## 正面项（本轮不要动）

- `app_loading.dart:198` 的 shimmer **已显式处理** reduce-motion（注释明写「减弱动态效果：停掉循环 shimmer」）——全站 reduce-motion 做得最规范的地方。
- `app_motion.dart:142-149` `PressScale` 在 reduce-motion 分支**保留了手势**，注释还记录了历史 bug（曾直接 `return child` 把 `GestureDetector` 一起丢掉，导致按钮点不动）。这是很好的回归防线。
- `assistant_cards.dart:32-34` 题卡的 `IntrinsicHeight` + `Row(stretch)` 处理正确（`MEMORY.md` 记过这个坑）。
- 题卡学科色条（`:316-319`，6px）符合「色块 ≤ 卡片 40%、列表行禁止整行填充」。
- `AppElevation.hard()` / `hardPressed()` 的硬阴影口径统一，`app_motion.dart` 的 `ConfettiBurst` 彩带取 `AppBrutal` 原色并注明「庆祝场景是唯一允许全铺的时刻」——克制得当。

---

## 建议执行批次

| 批次 | 内容 | 性质 | 前置依赖 |
|---|---|---|---|
| **A** | P0-1 ~ P0-4 | 缺陷修复，不涉及审美判断 | 无。可立即做，建议一个 commit 一题 |
| **B** | P1-2 + P1-3（焦点 + 大字档）合并做，先只改家长概览一屏 | 审美决策 | 需先定「哪张卡当焦点」 |
| **C** | P1-1 助手卡片类别色，先做 3 种卡片 | 审美决策 | 需先定语义族归并方案（本文给了 3 组草案） |
| **D** | P1-4 + P2-1 ~ P2-3 | 动效补齐 | 令牌层改动（`AppProgressBar` / `PopIn`）需先加守卫测试 |

**验证手段**：本仓已有成熟做法——widget 测试守几何实测值（如 `test/control_height_test.dart`）+ PNG 截图探针回看视觉（`MEMORY.md` 记录「渲染 PNG 回看是验证视觉修复的有效手段，用完立刻删探针」）。P0-1 的形状编码尤其适合截图回看，因为它是**只能看出来的**问题。

**批次纪律**：ADR-0044 要求「token 层先行 + 试点，禁止一次性全量重做」。批次 B/C 各只动一屏/一文件，跑通再扩。

---

## 落地结果（A/B/C/D 全部执行完毕 · 2026-09-17）

analyze `No issues found!`；`flutter test` **207 全绿**（开工前 194）。每个守卫都用反例探针验证过会红。

| 批次 | 落点（文件） | 新守卫 |
|---|---|---|
| A | 7 处裸 `GestureDetector` → `AppFocusableAction`/`AppIconAction`（`assistant_cards` / `assistant_message_list` / `parent_question_bank_view` / `interest_picker` / `parent_task_form_view` / `child_home`）；3 处手写空态 → `AppEmptyState.inline`（`mastery_board` / `parent_overview_view` / `parent_tutor_logs_view` + 补 import）；描边裸数字 1 处 → `AppElevation.borderWidthSm`（`parent_question_card:143`，其余 3 处随空态迁移与 `_StatCard` 删除消失）；`mastery_board` 纯色点 → `SubjectMarkIcon` | `no_bare_gesture_guard_test.dart`、`subject_mark_encoding_test.dart` |
| B | `parent_overview_view.dart`：4 张等权 `_StatCard` → `_StreakHero`（连续打卡，`AppBrutal.orange` + `hard()` + `displayLarge` 22px + w800）+ `_QuietStats`；`Row(stretch)` 包 `IntrinsicHeight` | 复用 `stretch_row_guard_test.dart` |
| C | `assistant_cards.dart`：`_familyFillOf(kind)` + `_CardHeader` 32×32 色底（cyan=待办/复习、magenta=错题/掌握、其余中性）+ `onColor` 前景 | 复用 `assistant_card_test.dart` |
| D | `app_theme.dart`：`AppProgressBar` 补 `TweenAnimationBuilder` 填充过渡 + `reducedMotionOf` 事实源迁入；`app_motion.dart`：`PopIn.delay`；`assistant_message_list.dart`：卡片错峰 + 阶段文案 `AnimatedSwitcher` | `progress_bar_transition_test.dart`、`pop_in_stagger_test.dart`、`assistant_stage_switch_test.dart` |

### 与本文诊断的两处出入（以代码为准）

1. **P0-1 被高估了**。原文断言 `SubjectMarkIcon`/`SubjectKey.mark` **零业务调用** —— 这是**读法错误**：
   `AppTags.subject` 返回 `_TagChip`，而 `_TagChip.build` 里确实渲染了 `SubjectMarkIcon(mark: subject!.mark, size: 9)`。
   三重编码的**形状层是通的**，`practice_question_view.dart:49,90` / `child_home.dart:391` 那几条注释也是对的。
   推断的漏洞在于：**只读工厂函数，没有读到工厂返回的那个私有组件内部的渲染**。
   真正缺的只剩 `mastery_board.dart` 的 10×10 纯色点（那里同行进度条已用颜色编码，形状是补第二重），已改。
2. **遗漏项 2 处**：裸 `GestureDetector` 实为 **7** 处（漏 `child_home.dart:223` 的 `Semantics(button)+GestureDetector`——
   有读屏语义但**不进焦点树**）；手写空态实为 **3** 处（漏 `parent_tutor_logs_view.dart`）。两处都是靠静态扫/按规则穷举才浮出来的。

### 透镜落不下去的地方（已放弃，不是欠账）

- **bolder 要的 3–5× 字号阶差本仓做不到**：`AppText._typeScale` 上限 `displayLarge` 22px、下限 12px → 最大 1.83×。
  要做到 3× 必须**新增字号令牌并补一个 ADR**。本轮选择「不为了透镜去动令牌」，改用「一屏只有一张彩色卡」制造焦点（批次 B）。
- **P2-3 的脉动没做**：气泡里的不确定态 `CircularProgressIndicator` 已在持续动，再叠一层呼吸是噪声，
  且对 reduce-motion 更不友好。只做了阶段文案的 `AnimatedSwitcher`。
- **P2-4（三套动效语汇并存）与 P1-1/P1-3 的全站铺开**仍待办，属下一轮。
