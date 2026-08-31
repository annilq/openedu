# 娃娃学习 — 设计系统语境

本文件定义设计令牌与组件体系中特有的术语。不含通用编程概念。

## Language

**Accent（靛蓝强调色）**:
用于 selection、focus、progress 填充、链接文字的单一强调色（`#5E6AD2` 亮 / `#7B82EA` 暗）。CTA 按钮不使用 accent，而用近黑底白字保持重量感。
_Avoid_: primary（已废弃的暖绿角色名）、brandColor、themeColor

**Surface 层次**:
五级表面色阶：surface（内容区微暖白）/ surfaceRaised（卡片 `#FFFFFF`）/ surfaceHover（hover 态 `#F4F4F2`）/ surfaceSunken（侧栏/凹槽 `#F4F4F2`）/ surfaceActive（选中态药丸 `#EDEDF0`）。禁止手动 withValues(alpha:) 透明度变体。
_Avoid_: backgroundColor、cardColor

**Outline（描边）**:
卡片/分隔线的 1px 极细描边（`#ECECEA` 亮 / `#2A2A28` 暗）。hover 时描边加深至 outlineHover（`#D1D1CE`）。Linear 风格——用描边分层，不用阴影。
_Avoid_: border、divider、stroke

**密排字号阶梯（Dense Type Scale）**:
正文 15sp 基线的统一字号体系，双端共用。Inter 主西文/数字 + HarmonyOS Sans SC CJK 回退。每个字号有对应 tracking（标题负、正文零、小字正）。行高按用途区分（标题 1.2 / 紧凑文字 1.35 / 阅读文字 1.5）。
_Avoid_: 护眼大字、20sp 基线

**语义色（Semantic Colors）**:
降饱和的四档状态色底——positive（极淡绿 `#EFF5EC`）/ warning（极淡琥珀 `#FAF3E8`）/ error（极淡红 `#FCE8E6`）/ info（极淡靛蓝 `#EEF0FC`）。用于 badge/chip/icon 容器，不用于大面积背景。
_Avoid_: primaryContainer/secondaryContainer/tertiaryContainer（旧暖绿体系角色名）

**转场分级（Motion Tiers）**:
三档动画时长——交互态 120ms / 状态切换 200ms / 页面进入 300ms。交互态用 easeOut，页面进入用 easeInOut。loading→loaded 用 crossfade。
_Avoid_: 统一 200ms easeOut（旧做法）

**Hover 令牌（Hover State）**:
桌面壳下所有可交互元素（侧栏项、卡片、按钮）的 hover 反馈——surface 变 surfaceHover、outline 变 outlineHover。用 MouseRegion 或 Shad hover 回调实现。
_Avoid_: 无（旧做法完全没有 hover）

**双模式（Dual-Mode，ADR-0014）**:
Parent Mode（家长工作台，密排专业 15sp 基线）与 Child Mode（娃娃学习台，~17sp 基线、更圆角、学科色凸显、适度趣味动效）。两者共用 surface/spacing/radius 令牌，仅字号阶梯、语气与学科色权重分化。由 `AppUserMode`（parent/child）独立于主题明暗切换。
_Avoid_: 为娃娃单独维护一套完全独立的颜色/组件库（应走令牌分化）

**学科色（Subject Accent，ADR-0014）**:
受控多色强调——数学=蓝 / 语文=玫瑰 / 英语=翠绿（中饱和，预留扩展槽）。仅用于学科标识、进度条、图标容器、小面积 chip；不作大面积背景。Parent Mode 数据可视化中低调使用，Child Mode 凸显。
_Avoid_: 高饱和荧光色、大面积学科色铺底、把学科色当全局强调色（全局强调仍是 accent 靛蓝）

**断点（Breakpoint，ADR-0014）**:
compact(<700) / medium(700–1023) / expanded(≥1024) 三档；compact 收起侧栏为底部导航（Child）/抽屉（Parent）。
_Avoid_: 写死 240 侧栏不自适应、用设备型号判断而非宽度

**Celebrate 动效（ADR-0014）**:
450ms easeOutBack 的徽章解锁/连击/打卡成功反馈，仅 Child Mode 启用；correct 题 scale-pop 120ms。
_Avoid_: 在 Parent Mode 触发庆祝动效、游戏化过度

---

## AI 出题（多学科试卷 + 题库快照，ADR-0004）

**Task（出题派发容器）**:
一次出题 + 草稿审核 + 派发 + 消费的容器。学科下沉到题。`status: draft → ready → assigned → done`。draft 可编辑题/删题/整卷重生成/逐题加入题库；ready 锁定可派发；assigned 派发只读快照；done 完成打卡。`specs`（JSON 数组）保存原始生成规格，用于整卷重生成。
_Avoid_: Paper、Exam（不引入此命名）

**Question（题库层）**:
`Question` 表本身即题库层（独立实体）。**草稿期 TaskQuestion 默认不预入库（R-Q1=c）**——家长在审核页点「加入题库」才真正写 Question，返回 `question_id` 给 TaskQuestion。家长删草稿题同时从 Question 层物理删除（R-Q5=b）。家长改题库不影响已派发任务（读 `TaskQuestion` 快照）。
_Avoid_: Paper、ExamBank、QuestionPool、QuestionBank（当前不引入此表）

**TaskQuestion（派发快照 / 草稿载体）**:
草稿期 = 审核载体（默认 `question_id` 为 null，未入库）；派发（`ready → assigned`）时深拷贝副本（当前实现草稿项和快照项共用一张表，派发即从 draft 冻结，不做二次拷贝）。绑 `task_id`，assigned 后只读。娃娃做题、批改、错题归集全部读 TaskQuestion，不读 Question。
_Avoid_: TaskQuestionSnapshot、FrozenQuestion

**batch-generate（多学科批量生成）**:
`POST /tasks/batch-generate` 接收 specs 数组，后端逐科循环调 `QuestionGenerator`。**只写 TaskQuestion 草稿项，不写 Question**（R-Q1=c），并把原始 specs 存入 `Task.specs` 以便整卷重生成。返回 `draft` 态 Task，家长进入审核页。
_Avoid_: multiSubjectGenerate、paperAssemble

**草稿（draft）/ 锁定（ready）/ 派发（assigned）**:
Task 三阶段流转。草稿支持「编辑题干+答案、删除单题、单题重生成、整卷重生成（按 `specs` 原规格全替换）、逐题加入题库」。锁定成卷（draft→ready）与派发给娃娃（ready→assigned）两动作分离（R-Q3：保存草稿返回、锁定、派发、作废 4 动作全有）。整卷重生成 = 全量替换 TaskQuestion + 清除所有已入库 Question（同草稿绑定的 Question 全删）。
_Avoid_: 生成即派发（旧 F-103 一键流程）、生成即预入题库（ADR-0004 旧做法已被 R-Q1=c 推翻）

**加入题库（Promote to Bank）**:
草稿审核期家长点某题的「加入题库」按钮：把该 TaskQuestion 字段深拷贝到 Question（题库层），并把 TaskQuestion.question_id 指向新 Question。已入题库的题再被删除草稿时，Question 层同步物理删（R-Q5=b）。草稿题若未入题库就被派发——派发前锁定阶段必须保证所有题已入题库？还是允许派发无 question_id 的题？——**不允许**：锁定成卷（draft→ready）时校验所有 TaskQuestion.question_id 非空，否则拒绝锁定。
_Avoid_: Promote、AddToBank（直接用「加入题库」中文）

**题目编辑字段边界**:
草稿期可编辑：**题干、选项文本、答案、解析**（R-Q4）；知识点、subject、grade、qtype、difficulty 不可改。要换知识点/题型/学科/年级/难度走「重生成」（单题 / 整卷）。
_Avoid_: 全字段可编辑（会破坏 specs 一致性，导致整卷重生成与当前草稿不一致）

**一键均分（Auto-split）**:
多科表单快捷按钮：输入总题数 + 选 N 个学科，自动等分到各学科行。默认按学科行逐科配置，家长可加/删行。
_Avoid_: 总数自动 AI 分配（家长对单科控制弱）

---

## 错误码（统一口径，E-Q1~Q4）

**错误码分层（E-Q1=a）**:
系统级 10xxx：`10001 Unauthorized` / `10002 Forbidden` / `10003 NotFound` / `10004 Validation` / `10005 ServerError`；业务级按领域分段：20xxx Tasks / 30xxx Auth / 40xxx Review / 50xxx WrongQuestions / 60xxx Tutor / 70xxx Children。每位调用方捕获都能看到数字 code + 文案。

**错误体（E-Q2=a / E-Q3=a）**:
错误时 HTTP 状态码保持语义（401=401、403=403、404=404、409=409、422=422、500=500），body 统一 `{"code":"TASK_20001"|20001, "message":"...", "status":403, "data":null}`。成功体不包层，保持原有直接返回结构。`code` 字段推荐用字符串（枚举 name + 数字，便于搜索），也可退回纯数字。

**前端呈现（E-Q4=a）**:
AppToast（即时提示）与 AppError（错误占位页）均展示为「E-<code>：<message>」的格式，方便一眼定位根因。
_Avoid_: 只显示中文友好文案不显示 code（调试线索丢失）
