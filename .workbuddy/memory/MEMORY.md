# openedu · 项目长期约定
> 权威设计在 `.impeccable.md`+`docs/adr/`+`docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。本文件只留实测数字/归因/操作纪律。

## 0. 环境/命令/多会话
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）。`flutter test` 关代理(`no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同，否则 WS 升级失败)~16s；`flutter analyze` 退出码常非0→认 `No issues found!`。
- 禁 `dart format`（本机 tall style 不同→噪声 diff）；只靠 analyze。新增原生插件须完整重跑 App。
- 多会话并行改共享文件：先看 `git status`+mtime，定点 Edit，写完回读（本文件被并发整写覆盖过两次）。
- 并行 worktree：`git worktree add /tmp/oedu-tXX -b ticket/XX <base>` + 软链 `<主仓>/backend/.venv` 与 `.env`；pytest 须 `PYTHONPATH=/private/tmp/oedu-tXX/backend`+`mv .env .env.hidden`+`--basetemp=/tmp/<新>`。前端 worktree 直接 `flutter test`。
- 本机 `grep` BSD 版→`grep -E`；`grep -c` 得0≠没有，用 Grep 复核。`/bin/bash`=3.2：`${VAR}` 防中文吞首字节；脚本被 zsh 调需 `exec bash "$0" "$@"`。
- 文案纪律：写「中小学」不写 K12（=1–9 年级义务教育，不含高中）；替换后查残留中英空格。
- 新 ADR 取号前查目录最大号+`git status docs/adr/`+memory 预留（撞过 0055/0058）。
- 提交材料 docx 走 `submission_docs/gen.py`；python-docx 默认 Letter→`set_col_widths` 钉列宽、run 显式 `set_run_font`；本机无 LibreOffice→只程序化校验。

## 1. 前端分层(ADR-0036/0037)
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。路由优先级即功能(ADR-0054)：写意图 `guide`(20)>只读 `query`(12)。
- 卡片动作 `actions=[{label,target}]`(target 非 URL)；`ShellDestination.fromTarget` 解读，两端同改。
- 结构化动作键=manifest `actions` 等值匹配(ADR-0081)：`task_generate`/`quiz_generate`/`courseware_hint`/`quiz_judge`。
- 出题唯一路径=`POST /tasks/generate`(流式)+`/tasks/from-generated`(落库)，服务端「重生成」全删(ADR-0084)。课件内容纯手动编排(ADR-0085)。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`。R4 棘轮：`presentation/` 禁 import `*/data/`(测试 `feature_boundaries_test.dart`)→用 data 类型搬 `domain/repositories/`。
- 非 push 路由页面禁裸 `Navigator.pop`（弹根栈=白屏）；走注入回调或 `maybePop`。

## 2. 视觉/控件实测
- 全仓禁用 Material 控件(`InkWell`/`Icons.`/`Scaffold`/`ListTile`/`Divider`/`Tooltip`)：根 `ShadApp`+`CupertinoApp` 无 Material 祖先→构建期抛「No Material widget found」且 analyze 照不出。可点区一律 `AppFocusableAction`。
- 描边三档 2/1.5/1；白物体纸底 `#FDFBF7` 无边界→补描边。空态 `AppEmptyState`(ADR-0051)；reduce-motion `reducedMotionOf(context)?Duration.zero:…`；浮层阴影 `_floatingShadows()`(暗色返 none)。
- `ShadButton.height` 是内容盒高，描边画盒外→可见高=值+2×描边宽(声明32实测40)；并排按钮一律 `Wrap`。
- `ShadCard` 高于内容→内容贴顶，钉高调用点自包 `Center`。`Row(stretch)` 须包 `IntrinsicHeight`（裸 stretch 必崩）；**但子树含 `LayoutBuilder`(如 `SceneInterpreter`)时 `IntrinsicHeight` 也崩**→改不依赖 intrinsic 布局；`Column(stretch)` 安全。色条用 `Stack`+左 `Container`+卡片 clip 裁圆角（非均匀 Border 喂 ShadCard 抛 `borders with uniform colors`）。
- ADR-0083 已废：几何权威源现归 `figure_library` 表+`SceneSpec{kind,figure?,options?,curated}`(ADR-0091 落地)。`figures.dart` 只 `FigureShape`+`kFallbackFigure`+`figureMatchingVertices`。
- 多图形不平铺：图形画廊(条目顺序=渲染顺序；卡宽 124 夹 2–6 列)+弹 `ReflectionSceneDialog`；画布边长 `min(420,屏高−320,屏宽−64)` 夹[220,420]。画廊只画不判。

## 3. 自适应布局(ADR-0045/0059)
- `AdaptiveShell` 两档：紧凑<700=娃娃底栏/家长抽屉；≥700=侧栏240↔64。
- 导航状态单一：`sealed ParentPage`/`TeacherPage`，所有入口只调 `_go(page)`；并列状态⇒必漏清。
- 文件规模棘轮(ADR-0058)：`test/file_size_guard_test.dart` 的 `_baseline` 只许下调，新文件>400行直拦；搬代码禁正则删方法(DOTALL 跨吞 body→逐行原样搬)。`AppTheme.colorsOf(context)` 返 `AppColors`。
- 内容兜底 `Align(topCenter)`+`ConstrainedBox`(非 `Center`)。push 整页走 `AppContentFrame`+`AppPushedPage`(`showBack`默认true)；勿手写 `AppTopBar(showBack:)`。

## 4. 测试/截图探针
- `ShadApp.custom(appBuilder:)` 不装 `ShadToaster`→widget 测试须显式 `ShadToaster(child:)`，否则 `AppToast.show` 抛错。
- 禁在 `test/` 写截图装置：`RenderRepaintBoundary.toImage()` 无真实合成器永不完成（实测 46s→17min）。改几何断言。
- 网络层加接口须同步 4 测试替身(`assistant_api_client_test`/`list_archive_test`/`review_notifier_test`/`students_notifier_test`)。
- 长按 `startGesture`+`pump(kLongPressTimeout)`；点按把 `holdToTalk` 显式传进组件。
- 静态护栏误报坑：子串匹配词边界锚定(`contains('BarChart(')` 被 `AppBarChart(` 骗，`2c7a320` 修)。

## 5. Git/后端/长列表
- 平台目录不在版本控制→补丁脚本(`patch_macos_network.py`/`patch_voice_permissions.py`)幂等+`--check`。常显 `Everything up-to-date` 却已成功→`git ls-remote origin main` 比对 HEAD。提交按逻辑批次拆、正文写「为什么」；`chore(memory):` 单独提交。
- `git commit -- <file>` 重暂存整个工作区→hunk 级 `git add -p` 后不带 pathspec `git commit`。
- 引擎失败归因：`decrypt()` 解不开只返 None；`ToolUnsupportedError` vs `ProviderRequestError(kind+user_hint)` 落 `genkit.py#classify_failure`；禁 `except Exception` 抹成「请添加模型」。
- 可空 JSON 列须 `JSON(none_as_null=True)`(ADR-0061)；SQLite「加列」≠「加约束」：改 UNIQUE 须重建表(先读 `sqlite_master`)。
- 选项标号只渲染层画且须剥模型前缀(ADR-0061 §T)：前端每处渲染过 `cleanOptionText`。
- pytest 前 `cd backend && mv .env .env.hidden`；`.venv/bin/pytest` 全量~25s；真库 `backend/app.db`→必先 `cd backend`。
- 学习闭环六段只通一段：仅「答错即建错题」(`tasks/service.py:1236`)。
- 长列表(ADR-0053)：keyset 游标；读错题加 `graduated_at IS NULL`。
- 分层不变量9：归属判定只许 `core.guard`(`require_owned`/`find_owned`/`require_owned_child`)，禁内联 `x.parent_id!=y`；AST 守卫 `tests/ai/test_layering_invariants.py`。改 `features/*/service.py` 必跑 `tests/ai/`。
- ADR-0064 多选删除：`POST /materials/bulk-delete`+`/materials/knowledge-points/bulk-delete`。
- ADR-0055 资料库+RAG：4 表全带 parent_id；BGE-M3；`EMBEDDING_MODEL` 兼向量版本戳；`build_retriever(session,parent_id)`。
- ADR-0073 场景库：`KnowledgePoint.scenes` 唯一事实源；`SCENE_LIBRARY` 仅作者辅助、渲染/生成永不回查；`figure` 绝不预填；`get_builtin_scene` 必返深拷贝；统一入口 `resolve_kp_scene`。
- 同一实体两份 schema：`features/*/service.py`(助手工具投影)与 `router.py`+`schemas.py`(REST)。前端打 REST。交互讲解读路径唯一入口 `scene_spec_for_read`(ADR-0061 §U)。

## 5b. 场景/图形（ADR-0091 已落地）
- `Figure`(`app/domain/figures.py`，纯数据)=`{key,label,points,edges}`，只与渲染有关。前端复用 `FigureShape`。`Figure` 是 `SceneSpec` 几何子集。
- 选项 `options: list[{text, figure?}]`：`text` 恒存、`figure` 几何内联、**全-or-无挪校验层**。同 JSON 列无 DDL；`normalize_options` tolerant read+判题走 `option_texts`。
- 目录投影+校验+盖章模块 `app/features/materials/figure_stamp.py`：输入 `kp.scenes`(curated 优先)→回落 `figure_library`；目录条目 `FigureRef{key,label}`。
- **`scene_extract.py` 已删**（ADR-0089-03 清债完成，commit `1ccb6d3`）：`extract_option_group`+`extract_scene_inputs`+整模块删除；`default_scene_from_figure`→`scene_spec_from_figure`（已在 `scene_fusion.py`）。tutor agent 改走 `resolve_interactive_scene`（`ai/subagents/tutor/scene_intent.py`）。
- 答疑出图三层（ADR-0089-03 落地）：L0 确定性门控(解析知识点+非空目录，不调模型、不用意图关键词→断言微调用=0)→L1 一次结构化 `SceneIntent{should_show,figure_key,rationale}`(`provider.stream(schema=SceneIntent)`)→L2 后端校验盖章(`accept_scene_intent` 四态全不发射：不该出/给键却不该出/键不在目录/通过返回键)。模型只建议身份键(无顶点)、无决定权；未命中/异常不发射且正文照常；连续同 key 去重(`last_scene_figure_key`)。kind 首版恒 `reflection`。

## 6. 题型模型(ADR-0004 D5)
- qtype `{choice,fill,calc,open}`。选择题须≥2 有效选项(`TASK_CHOICE_NO_OPTIONS(422)`)。多选 `multi:bool` 仅 `qtype=='choice'`。
- 判断题= `choice`+对/错二选一(`isJudgeQuestion`)。ADR-0090：`Conversation.pending_quiz` 已删；`chat()` 直接 `IntentSignal(text,action)`。tutor 经 `_read_history`→`_question_card_text` 渲染题干/选项/正确答案/解析。

## 7. 班级管理（ADR-0068 后端 + 0086 前端）
- 后端已全落地：`Class`(`teacher_id,name,grade(1–9)`)+`User.class_id`；`/classes` CRUD+`student_count`；`/students?class_id=&keyword=`+批量移班+导入导出+级联删。`POST /students` 与 `/students/import` 增可选 `class_id`。
- 前端缺口：`features/classes/` 缺 `presentation/`；ADR-0086 补「班级管理」一级导航(`TeacherPage.classManagement`)+班级下钻学生管理页。
- 年级语义：学生不持年级，`user.grade` 全删；年级由 `Class.grade` 承载。消费方经 `user.class_id`→`class.grade`，入口 `assistant.service._student_grade`(未分班返 0)。

## 8. AI 运行轨迹可观测（ADR-0088 进行中）
- 端点：`GET /ai/debug/conversations`、`GET /ai/debug/conversations/{conv_id}`（已接 `require_owned_or_admin`；admin 见全部 `teacher_id=None`）。`Message` 模型有 `payload/content/input_safe/output_safe/blocked/block_reason/latency_ms/usage`。
- `Role` 枚举 STUDENT/TEACHER/ADMIN；`require_admin`/`CurrentAdmin` 存在（admin=super-teacher）。`ErrCode`：FORBIDDEN/SYS_10002(403)、NOT_FOUND/SYS_10003(404)。
- 进行中票：0088-03 脱敏+破窗（默认掩码学生 PII，破窗显原文+写审计日志，未授权全文 403/404）；0088-04 e2e 回归+收口 ADR §7 三问+同步 CONTEXT.md。

## 9. 集成/工单跟踪
- ADR-0091 全部 6 票 `done`（集成分支 `integration/adr-0088-0091`）。0088-00/01/02 已合；0091 全合。
- ADR-0089：01/02/03/04 全 `done`（commit `2a826bc`/`2fc3cd1`/`1ccb6d3`/0089-04 本轮）。04 = 前端选项内联图形（`QuizOption{text,figure?}` 替换 `List<String>`；`AppOptionTile` 行内缩略图+点图形弹 `ReflectionSceneDialog`；复用 `FigureThumbPainter`/`FigureShape`，零新增图形类型）。`flutter analyze`+`flutter test` 全绿。
- ADR-0088：00/01/02 已合；**0088-03/04 待做**（脱敏+破窗 / e2e 收口，`.scratch/ai-run-trace-observability/`）。
- **ADR-0090 = `.scratch/quiz-loop-subagent/`**（4 票 01–04，均 `ready-for-agent` 未翻 done；对应 `docs/adr/0090-spec.md`）。实现曾在 `2c37fa0`/`e035757`/`fce6b07`/`aeeaf51` 落地（判断题闭环子代理化），但**工单状态未回写**=陈旧状态字段的典型。开工前先 `git worktree add /tmp/oedu-head HEAD` 归因既有红，再决定翻 done 还是补做。
- 本地 tracker：`scene-aware-ai-loop/`(0089 系列)、`ai-run-trace-observability/`(0088 系列)。
