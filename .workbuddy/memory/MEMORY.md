# openedu · 项目长期约定
> 权威源 `.impeccable.md`/`docs/adr/`/`docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。

## 0. 环境/命令
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）；`flutter test`/`analyze` 须 `no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`（WS 升级失败）；`flutter analyze` 退出码非0→认 `No issues found!`。禁 `dart format`（tall style 噪声）。
- 并行 worktree：`git worktree add /tmp/oedu-tXX -b ticket/XX <base>`+软链 `backend/.venv`/`.env`；worktree 下 pytest 须 `PYTHONPATH=/private/tmp/oedu-tXX/backend`。
- 后端 pytest：`cd backend` 先 `mv .env .env.hidden`（真库 app.db，已被 gitignore）；全量必带 `--basetemp=/tmp/<新目录>`（沙箱拒默认 temp 的 mkdir → 大量 setup ERROR，易被误判回归）；跑完 `mv .env.hidden .env`。`.venv/bin/pytest` + `.venv/bin/ruff`。

## 1. 前端分层/控件（analyze 照不出）
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。结构化键=manifest `actions`(ADR-0081)：`task_generate`/`quiz_generate`/`courseware_hint`/`quiz_judge`。单向 `main/→features/*→shared/*`；R4：`presentation/` 禁 import `*/data/`。
- 禁用 Material 控件(`InkWell`/`Icons.`/`Scaffold`/`ListTile`/`Divider`/`Tooltip`)：根 `ShadApp`+`CupertinoApp` 无 Material 祖先→抛「No Material widget found」。可点区一律 `AppFocusableAction`。
- `ShadButton.height` 可见高=值+2×描边宽；`Row(stretch)` 须包 `IntrinsicHeight`（**子树含 `LayoutBuilder` 也崩**）；`Column(stretch)` 安全。`ShadCard` 高于内容→调用点自包 `Center`。色条=`Stack`+左 `Container`+卡片 clip 裁圆角。白物体纸底 `#FDFBF7`→补描边。
- 自适应 `AdaptiveShell`：<700=娃娃底栏/家长抽屉；≥700=侧栏240↔64。文件规模棘轮(ADR-0058)：新文件>400行直拦；搬代码禁正则删方法。push 整页 `AppContentFrame`+`AppPushedPage`(`showBack`默认true)。
- 测试：`ShadApp.custom(appBuilder:)` 不装 `ShadToaster`→widget 测试须显式 `ShadToaster(child:)`。禁截图装置（`RenderRepaintBoundary.toImage()` 无合成器永不完成→改几何断言）。长按 `startGesture`+`pump(kLongPressTimeout)`。

## 2. Git/后端纪律
- 提交按逻辑批次拆、`chore(memory):` 单独提交；`git add <部分>` 后**不带 pathspec** `git commit` 会连带提交索引里已暂存删除/改名→提交前必 `git diff --cached --stat` 核对。`git worktree remove -f <path>` 一次一个；删分支 `git branch -d`（须已 `--merged`）。
- 引擎失败：`decrypt()` 解不开只返 None；`ToolUnsupportedError` vs `ProviderRequestError(kind+user_hint)`；禁 `except Exception`。可空 JSON 列须 `JSON(none_as_null=True)`(ADR-0061)；SQLite「加列」≠「加约束」→改 UNIQUE 须重建表。
- 归属只许 `core.guard`(`require_owned`/`find_owned`/会话三件套)，禁内联；AST 守卫 `tests/ai/test_layering_invariants.py`。改 `features/*/service.py` 必跑 `tests/ai/`。同一实体两份 schema：`features/*/service.py`(助手投影)与 `router.py`+`schemas.py`(REST)。
- 已知环境性红：`tests/api/routes/test_materials.py::test_empty_text_422`（clean tree 也失败，与本工作无关）。

## 3. 意图路由终态（ADR-0104/0105/0101，2026-10-20 落地）
- **规则（关键词/启发式）路由整体移除**。链路：动作直配（ADR-0081 等值匹配，永远最前）→ `decision`（LayaDecisionModel，`agent_core/adapters/laya.py`，**仅 `laya-multilingual`**，英文构造即 ValueError）→ `llm`（`classify_llm`，`adapters/llm_route.py`，`RoutingDecision` 只落适配器保内核 stdlib-only）→ 都不命中 → **无命中引导**：声明 `fallback_guide=True` 的业务（生产=capability 能力自述，零 LLM 固定清单，ADR-0105）。执行体（tasks/tutor）必须被显式路由到，`min(priority)` 仅无声明时最后防线（当前不可达）。策略 `AI_ROUTING_STRATEGY`：`auto=[decision,llm]`（默认）/`decision=[decision,llm]`/`llm=[llm]`。
- `decide(history=…)` 全量透传（近期 12 轮裁剪）；manifest name/description/actions 经 `_capability_text` 作候选。
- **测试确定性**：路由桩显式表态 `FakeLLMProvider(route_to=...)`（schema=RoutingDecision 时）+ `RoutingFakeProvider`；**禁止在替身里复刻关键词匹配**。都不命中恒落 capability（契约「至多一个 fallback_guide 声明 + 双端可见」守护）；学生 TutorLog 仅显式 tutor 轮落库。
- **聊天出题 = 纯 LLM 自由文本（用户接受的 UX 降级）**：无澄清引导/规格回显/specs 注入；按规格结构化出题仍走 `POST /tasks/generate`。通用槽位引擎保留但聊天层暂不可达（manifest 全 optional）。出题触发词缺口已修（ADR-0101 正则 `出[0-9一二…十两几]+\s*(道|题|个题|道题)`）。早前「流式题卡无 scene_spec」已过时——ADR-0102/0103 已在流式帧盖 scene_spec（受知识点是否配场景模板约束）。

## 4. 会话归属（ADR-0096）/题型/班级
- 判据唯一真源 `core.guard.conversation_owner_clause(user)`：学生 `student_id==me`；教师/admin `teacher_id==me AND student_id IS NULL`（教师**看不**到学生的）。三消费者（list/require_owned/owned_ids）同源，分家必出「列表能列出、详情 403」。
- `Conversation.teacher_id` ≠ 归属（表教学域/RAG 范围）；不加 `owner_user_id` 列。前端无只读态，列表单段可续接；历史学生会话留库不删。审计走 `/ai/debug/conversations`(`require_owned_or_admin`)。
- 题型(ADR-0004)：`qtype {choice,fill,calc,open}`；判断题=`choice`+对/错；`pending_quiz` 已删(ADR-0090)。班级(ADR-0068/0086)：`Class(teacher_id,name,grade 1–9)`+`User.class_id`；年级由 Class 承载，`user.grade` 全删。

## 5. 决策模型（本地 Ollaya 服务，2026-10-20）
- 服务：`ollaya` 0.15.0 `/usr/local/bin`，监听 `127.0.0.1:11435`（与 Ollama 11434 并存），TypeSafe `POST /v1/systemone`；模型 `~/.ollaya/models`。已拉 `laya:multilingual`(683MB)/`largha`(328MB)。
- **契约 payload**=`{model, state, questions:{id:{type:"choice",instructions,criteria:{业务键:capability_text}}}}`；响应 `answers[id].{choice,confidence,probabilities}`。门控用 `probabilities` top 值（TypeSafe `confidence=(K·pmax−1)/(K−1)` 跨可见集 K 不可比）。
- 参数/env：`OLLAYA_URL`（可选 `OLLAYA_MODEL`）；模型白名单 `laya:multilingual`/`largha`（英文权重构造即 ValueError）。超长 state→`422 STATE_TRUNCATED`→predict None→回落 LLM 分类（设计降级）。
- **中文实测**：13 用例+12 轮长历史，`laya:multilingual` 8/13=62%、p50 23ms、不截断；`largha` 5/13=38%、长历史 422 截断→**不采用**。最坏：学生「23+45怎么算」被 0.913 判 capability。纪律：候选模型须有本项目中文数据；评测跑在 pytest 外。
- 本机：Apple silicon 走 MLX(10–30ms)；虽有 HTTP_PROXY 无 no_proxy，urllib 对 localhost 自动绕过（**勿**加 ProxyHandler 旁路）。

## 6. 路由调优次序（ticket 12/13，用户 2026-10-20 定序）
- **文案 → 门控 → 权重**。ticket 12 **已 done（2026-10-21）**：脚本改吃生产投影（`discover_subagent_manifests`+`_capability_text`）消除手抄副本；顺带发现**学生端可见集被写成 K=2、生产实为 K=3**（tasks 对学生可见，ticket 11 那条「学生 23+45 被 0.956 判 capability」是在错选项集上测的）。34 条计分用例 + 10 条留出，基线 59%；七轮单变量爬山后 **74%**（采纳且正确 15→24/34，未采纳落引导 10→2），p50 23 ms、长历史不截断。
- **criteria 文案三条实测教训**（已写进 manifest 注释 + `tests/ai/test_routing_criteria.py` 契约测试）：① **禁止排他式否定句**（「不查数据/不出题」→35%，高置信错 6 条）；② **禁止堆示例问句**（50%）；③ capability **不要窄化成「只在问助手自身」**（44%）。capability 的「能做什么、不能做什么」对称措辞有效，不在禁止之列。
- **收益性质（重要）**：留出集 top-1 未提升（60%→60%），提升全在「正确路由过得了 0.5 门控」（30%→50%）→ 文案改的是**置信度分布**而非排序能力；下一步该动门控（ticket 13）。未达成验收项：新增 2 条高置信错误（查数据→tutor）、学生端 S01 未翻正（capability 0.56）。
- ticket 13（`needs-decision`，等 12 的数据）：把阈值从适配器构造参数上移为 runtime 的**声明式门控**（决策模型只出分布、runtime 决定是否采纳；LLM 的 confidence 一并纳入——今天它完全没被门控），再谈「学生端单独阈值」与「与 LLM 交叉校验(consensus)」。否决：把 role 塞进适配器、把 consensus 设为默认（每轮多一次 LLM 往返）。
- **capability 误判代价不对称**：判成 capability 与「都没命中」在用户侧同形（ADR-0105），判成执行体会答非所问 → 不应共用同一采纳门槛。
- **`routing_criteria`（ADR-0106，ADR-0097 单一事实源的有据例外）**：可选 manifest 字段，`_capability_text` 用它替换 `description`（name/actions 照旧，未声明行为不变）；**用户可见清单 `capability_catalog` 仍直读 `description`**。启用理由有实测：把「教师可管理题库/组建草稿任务」留在路由文案里准确率 74%→56%，但删了它用户就少一条真实能力 → 两份文本分离。契约测试守「清单显示的 == description」+ 长度 ≤120 + 无排他否定/示例问句 + 各具专属动词。
- 改 `description` 会同时改用户可见能力清单（`capability_catalog`「name：description」）与轨迹业务名 → 同步核对 `test_capability_subagent`/`test_assistant`/`test_tasks_subagent`/`test_intent_routing_contract`/`test_agent_runtime` 的断言；**只更新断言不改语义**。

## 7. 分支卫生 / ADR 状态
- 本地长期只有 `main`；integration/ticket 分支合入即删（`git branch -d` 保护未合入）。「记录说合过了」不可信，以 `git branch --no-merged main` 与 `git log main..<branch>` 实测为准。
- ADR 状态：0088/0089/0090/0091 全 done。ai-redundancy-cleanup spec（T01 死壳/T02 tutor伪帧/T03 共享invoke_subagent/T04 剥llm_route规则文本/T05 重命名`app/features/ai`→`agent_debug`）已 **`--no-ff` 合入 main**（2026-10-21）；全量 1026 passed/2 skipped/1 环境性红。未推 origin（gh 未登录，`.scratch/` ticket 仅本地草稿）。
