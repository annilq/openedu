# openedu · 项目长期约定

> 权威设计/令牌/原则在 `.impeccable.md` + `docs/adr/0044–0060` + `docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。本文件只留**实测数字/归因/操作纪律**。⚠️ 注入上限 ~11.5k 字符，超出不可见：新增前先删等量旧话。

## 0. 环境/命令/多会话
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）。`flutter analyze` 退出码常非0 → 认 `No issues found!`。⚠️ `flutter test` **必先关代理**（`no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`，否则 `Invalid WebSocket upgrade request`），全量~16s。
- ⚠️ 禁 `dart format`（本机 tall style 不同 → 85/118 文件噪声 diff）；只靠 analyze。
- ⚠️ 多会话并行改共享文件：先看 `git status`+mtime，定点 Edit，写完回读（本文件被并发整写覆盖过两次）。
- ⚠️ `flutter test` 慢先查游离 `flutter_tester` 进程占 `build/test_cache` 锁 → kill。新增原生插件须完整重跑 App（Hot Restart 不补原生注册 → pigeon `channel-error`）。
- ⚠️ 本机 `grep` 是 BSD 版，不支持 `a\|b` → 用 `grep -E`；`grep -c` 得0不等于没有，用 Grep 工具复核。
- ⚠️ **新 ADR 取号前查目录最大号 + `git status docs/adr/` + memory 预留**（撞车三次：0055/0058）。
- ⚠️ ADR-0061（资料库/场景）改动在 working tree 未提交，与已提交 D5 改动分离；提交前 `git status` 确认范围。
- ⚠️ **SwiftPM 依赖解析走 libgit2**：不读 `http_proxy`/系统代理，也**不认 gitconfig 的 `insteadOf`**（那是 git 命令行特性）；唯一生效的是 SwiftPM mirror（`~/.swiftpm/configuration/mirrors.json` + 工程 `xcshareddata/swiftpm/configuration/mirrors.json`，schema `{"version":1,"object":[{mirror,original}]}`）。gitconfig `safe.bareRepository=explicit` 会让 libgit2 拒开裸库、报同样的「Couldn't get the list of tags」。本机验证用 `swift package resolve --disable-sandbox`（沙盒下必须关沙盒），不必跑 xcodebuild。脚本 `frontend/scripts/patch_spm_cwl_mirror.py`（幂等+`--check`）。

## 1. 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。**助手路由优先级即功能**（ADR-0054）：写意图走 `guide`(20)；不高于 `query`(12) 被只读查询接走。
- **卡片动作受控枚举** `actions=[{label,target}]`，target 如 `parent_create_task`（非 URL）；前端 `ShellDestination.fromTarget` 解读，认不出即不动；**新增 target 两端同改**（`guide/agent.py`+`fromTarget`）。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`；`App*` 只给 `shared/widgets/`；各 feature 有 repository、不建 datasource。
- ⚠️ **R4 棘轮 `presentation/` 不得 import `*/data/`**（`test/feature_boundaries_test.dart`，`_knownR4` 自 2026-09-15 起为空、不得回退）。要用 data 类型 → 先搬到 `domain/repositories/`，data/ 只留 `Impl`。
- ⚠️ **非 push 路由页面禁裸 `Navigator.pop`**（弹根栈最后一条=整个App→白屏）；走注入回调或 `maybePop`。

## 2. 视觉/控件实测（取值见 `.impeccable.md`）
- ⚠️ **全仓禁用 Material 系控件**（`InkWell`/`Icons.`/`Scaffold`/`ListTile`/`Divider`/`Tooltip`）：App 根是 `ShadApp`+`CupertinoApp`，**整棵树无 Material 祖先**，构建期即抛「No Material widget found」、整片区域崩掉。**`flutter analyze` 照不出来**（类型全合法，只有真机构建才炸）→ 新控件测试须在**不套 Material** 的树里真构建一次（先例 `test/assistant_sources_bar_test.dart`）。可点区一律 `AppFocusableAction`。
- 描边三档：2 `borderWidth`·1.5 `borderWidthSm`·1 `borderWidthHairline`（顶栏底边/侧栏右缘/分隔线）。
- ⚠️ **白物体在纸底没边界**是头号陷阱：`surfaceRaised` vs 纸底 `#FDFBF7` 仅差~1.02 → 补描边非加粗。
- 空态 `AppEmptyState`(ADR-0051)。reduce-motion 须 `reducedMotionOf(context)?Duration.zero:…`；浮层阴影 `_floatingShadows()`（暗色返 `none`）。
- ⚠️ **`ShadButton.height` 是内容盒高**，描边画盒外 → 可见高=值+2×描边宽（声明32**实测40**）；收口 `AppControl.buttonContentHeight()`；并排按钮一律 `Wrap`。图标按钮 `AppIconAction`、行内 `AppTextAction`。
- ⚠️ **`ShadCard` 比内容高时内容贴顶不居中** → 钉高调用点自包 `Center`。`Row(stretch)` 须包 `IntrinsicHeight`；`Column(stretch)` 安全。
- **高度=触控锚点逐阶下推**：`heightLg`=48，标准−`step`(8)，紧凑−2×`step`；调档只改锚点。
- ⚠️ **`ReflectionSceneWidget` 画布边长=宽度正方形**（ADR-0061 §O）：顶点经 `frontend/scripts/gen_figures.py` 构建期从后端 `materials/scene_figures.py` 生成（`figures.dart` 为 const 产物，house 兜底前端独有），parity 测试 `test_frontend_figures_are_not_stale` 钉住；双副本手动同步约定已被取代（ADR-0061 §O 加注）。
- ⚠️ **多图形不再平铺（ADR-0061 §V）**：`optionGroup` → 图形画廊（**整库 11 个**卡片，列数只按可用宽度算，目标卡宽 124 夹 2–6 列）+ 点卡片弹 `ReflectionSceneDialog`（框里放完整场景，交互一件不少）。⚠️ 弹窗画布边长须按**屏高**夹 `min(420, 屏高−320, 屏宽−64)` 再夹 [220,420]，否则 1024×768 横屏顶出屏幕。画廊**只画不判**（出现「✓轴对称」= 泄答案）。
- ⚠️ **`reducedMotionOf` 事实源在 `shared/theme/app_theme.dart`**；别 `export … show` 转出（6处 `app_motion` import 变 `unnecessary_import`）。

## 3. 自适应布局（ADR-0045/0059）
- `AdaptiveShell` 两档：紧凑<700=娃娃底栏/家长抽屉；≥700=侧栏240↔64。`largeMin 1200` 无消费者。✅ 适配层实测完好（九档×两模式零溢出）。
- ⚠️ **导航状态必须单一**：家长端 `sealed ParentPage`，所有入口只调 `_go(page)`；并列状态⇒必漏清且 analyze 照不出。
- ⚠️ **文件规模棘轮**（ADR-0058）：`test/file_size_guard_test.dart` 的 `_baseline` 只许下调，新文件>400行直拦。基线14→**11条**（759/458 已达标）。事实源是测试 `_baseline`。
  - ⚠️⚠️ **搬代码块时禁用正则删方法**：DOTALL 下 `.*?` 会跨进下一个方法把它的body 吞掉（实测 58 个编译错）。✅ 正确做法：**逐行原样**搬，只对要改的行做 `line.strip() == '...'` 判定后单行 replace；helper 一律保留、只改签名。
  - ⚠️ `sed -n 'a,bp'` 带**尾随换行** → `split('\n')` 末元素是 `''`，assert 前先 pop。
  - ⚠️ `AppTheme.colorsOf(context)` 返回 **`AppColors`**（不是 ColorScheme）。
- ✅ **桌面窗口地板 320×568**（推翻800×600）；三处 runner 同改。⚠️ 六平台目录未进版本控制 → 改完须 `flutter build`。
- ⚠️ **内容兜底须 `Align(topCenter)`+`ConstrainedBox`，不可 `Center`**。⚠️ **`Navigator.push` 整页走 `AppContentFrame`**（唯一出口）+退路 `AppPushedPage`(`showBack`默认true)；勿手写 `AppTopBar(showBack:)`（默认false锁死一屏）。⚠️ 浮层宽令牌指外框宽，内容侧减 `popoverChrome`。

## 4. 测试/截图探针
- 五个坑（`runAsync`/`ShadApp.custom` theme/pdfx/`pumpAndSettle`/MediaQuery 注入位）见 `docs/agents/frontend.md` §7。
- ⚠️ **`ShadApp.custom(appBuilder:)` 不装 `ShadToaster`**（只有传 `child` 的 `ShadAppBuilder` 才包）→ widget 测试里用 appBuilder 必须显式 `ShadToaster(child:)`，否则 `AppToast.show` 抛「Could not find ShadToaster」。生产走 `CupertinoApp.builder`+`ShadAppBuilder(child:)`，不受影响。
- ⚠️ 测试里改 `debugDefaultTargetPlatformOverride` **在 tearDown 复位不及**（`_verifyInvariants` 早于 test 包 tearDown）→ 别改平台；要测长按就用 `startGesture`+`pump(kLongPressTimeout)`，要测点按就把 `holdToTalk` 显式传进组件。

## 5. Git/后端/长列表
- ✅ **平台目录不在版本控制 → 对策已定为「打补丁脚本」**（非纳入版本控制）：脚本在 `frontend/scripts/`（`patch_macos_network.py` 网络权限、`patch_voice_permissions.py` 语音权限 ADR-0063 §10），幂等可重跑，支持 `--check`（缺则退 1，把静默失效变成 CI 可见失败）。清单见 `CONTRIBUTING.md` §平台目录补丁。⚠️ macOS 沙盒下麦克风还需 entitlements `com.apple.security.device.audio-input`（缺则静默被拒）。⚠️ 常显 `Everything up-to-date` 却已成功 → 以 `git ls-remote origin main` 比对 HEAD 为准。提交按逻辑批次拆、正文写「为什么」；`chore(memory):` 单独提交。
- ⚠️ **`git commit -- <file>` 会重暂存该文件整个工作区再提交**：hunk 级拆分须 `git add -p` 后**不带 pathspec** `git commit`，否则未选 hunk 一并进（误并 ADR-0061 `multi`/`scene_spec` 翻过车）。
- 引擎失败归因：`decrypt()` 解不开只返 `None`；`ToolUnsupportedError`(无FC) vs `ProviderRequestError`(带 `kind`+`user_hint`) 落 `genkit.py#classify_failure`；禁 `except Exception` 抹成「请添加模型」。
- ⚠️ **可空JSON 列一律须 `JSON(none_as_null=True)`**（ADR-0061 §N/§T）：否则 `None` 被序列化成**文本 `'null'`**（非 SQL NULL）→ `IS NOT NULL` 为真而内容空、「有选项」类判断全走偏。**已全仓统一（12 列）**。迁移 `_nullify_text_json_nulls` 收拾存量（幂等，只UPDATE 值恰为 `'null'` 的行）。
- ⚠️ **选项标号只能由渲染层画，且必须同时剥模型前缀**（ADR-0061 §T）：后端 `normalize_options` **刻意不剥**（答案字段也带前缀，剥离会让判题失配）→ 前端**每处**选项渲染都要过 `cleanOptionText`。守卫测试 `tests/ai/test_option_prefix_contract.py` 逐点断言 + 不变量「**画标号 ⊆ 剥前缀**」（纯文本卡片手工画标号合法，故不能禁止）。
- ⚠️ **SQLite「加列」≠「加约束」**（ADR-0061 §R）：`ALTER TABLE ADD COLUMN x` 里写的 `UNIQUE(...)` 子句被**静默忽略**（无 `ADD CONSTRAINT`）→ **老库仍留旧约束而新建库正常**，本地测不出来。改 UNIQUE 只能**重建表**（建新表→`INSERT..SELECT`→删旧→`RENAME`→重建索引），迁移须**幂等**（先读 `sqlite_master` 判现状）；回归测试要**手工造老库形状**。旧约束更严时重建必安全（不可能已有重复行）。
- 工具 schema strict(ADR-0040)：可省略参数有缺席编码(`""`/`0`/`NO_FILTER="all"`)。助手分流(ADR-0043)：`acc` 只收 TEXT。
- pytest 前 `cd backend && mv .env .env.hidden`（完恢复）；`.venv/bin/ruff`、`.venv/bin/pytest`（全量~25s）。⚠️ **沙盒里必须加 `--basetemp=/tmp/<新目录>`**，否则 `tmp_path` 用例集体 PermissionError(EEXIST) 变 ERROR，会被误判成回归。⚠️ **真库 `backend/app.db`**（相对 backend），根目录跑迁移静默建空库 → 必先 `cd backend`。⚠️ 既存顺序污染失败 **4 个**（原记 3 个）：vectorize/retrieval 3 个 + `TestKnowledgePoints::test_confirm_flips_all_semester_variants`（它假定 `select(User).first()` = 自己的 fixture 家长），干净树全量同败、单跑过。勿误判。
- **「测试连接」**（2026-09-20）：走后端 + `build_engine` 同源；失败 200+`ok=false`；超时 `MODEL_PROBE_TIMEOUT_S=20`。⚠️ **探针首帧即停**：`cancel()` 后判 `done()` 再 await（401 时一帧无、channel 静默 `StopAsyncIteration`，不 await 会把认证失败判成成功）。
- **本地 Ollama 慢≠探针慢**：切模型权重换入内存真花~16s，同模型再测0.67s。
- **产品定位**（2026-09-21）：家庭自用+轻量开源（自部署）；README 只放产品，技术在 `CONTRIBUTING.md`。
- ⚠️ **「AI 编造数据」≠越权**：先查 message 轨迹有无 `tool_call`/`tool_result`（有必落库）；无=工具没执行、模型编。**流式改 FC 行为**：`ministral-3:3b` `stream=true` 零 tool_calls 编正文、`stream=false` 正确返回；`qwen3:1.7b` 流式正常。
- **学习闭环六段只一段通**：仅「答错即建错题」(`tasks/service.py:1236`)；出题不消费错题/掌握度(`question/pipeline.py:45-111` 零引用)。修法 ADR-0060。
- **长列表(ADR-0053)**：keyset 游标；追加在途换条件会拼回旧页→await 后重读；两列用 `Row`+`Expanded`(阈值1048)；读错题加 `graduated_at IS NULL`；迁移走启动期幂等 DDL。
- ⚠️ **分层不变量9：归属判定只许走 `core.guard`**(`require_owned`/`find_owned`/`require_owned_child`)，禁内联 `x.parent_id!=y`；AST 守卫 `tests/ai/test_layering_invariants.py` 全仓扫。改 `features/*/service.py` 必跑 `tests/ai/`。
- **ADR-0064 多选删除（2026-10-06）**：`POST /materials/bulk-delete`（`{ids, cascade_knowledge_points}` 默认 False）+ `/materials/knowledge-points/bulk-delete`。⚠️ **删资料的知识点连带 = 只删孤儿**（`repository.prunable_knowledge_points` 三条：同 `(subject,grade,semester,name)` + **无其他留存资料引用**（须 `exclude_material_ids` 排除本批，否则同批互相担保）+ `source=emerged && status=pending`）。因 **KP↔Material 无外键、只靠名字串**（同名 upsert 共享 / 学期是第四维 / curated=家长资产）。学期口径须与提取时逐字一致。
- **ADR-0055 资料库+RAG（2026-10-04 定稿+实现 B1–B7）**：4表全带 parent_id；向量存 BLOB 暴力扫；dense+sparse+RRF(BGE-M3)。`EMBEDDING_MODEL` 兼向量版本戳（改名=全量 stale）。`build_retriever(session,parent_id)` 新签名。黄金集 Hit@5=100%/Recall@5≥0.85。遗留：OCR/reranker/pgvector/英语分层。**已用到 0073（0063=助手语音输入、0064=多选删除+KP级联、0065=教师/学生重定位、0066=知识点来自资料、0067=按知识点课件、0068=班级实体与学生管理、0069=作业批量派发、0070=导航重构与学情统计、0073=场景库），下号前查目录+git status+本文件**
- ⚠️ **ADR-0073 场景库（2026-10-08 已实施）**：**`KnowledgePoint.scenes` 是唯一事实源**，恒存完整已解析副本；后端 `SCENE_LIBRARY`（`materials/scene_templates.py`）**仅作者辅助**（编辑器预填 + 浏览页枚举），**渲染/生成永不回查注册表**；**无 `scene_name` 列**，kind 标识取 `scenes[].kind`。注册表条目须保标准 SceneSpec 形状（`inputs[].key`），改 `{name,value}` 会让前端解析全空；**`figure` 绝不预填**（house 兜底仅前端 `figures.dart` 独有）。`get_builtin_scene` 必返深拷贝（进程级共享常量污染只在第二个知识点现形）。统一入口 `resolve_kp_scene`（薄读取器，不合并）。`GET /materials/scene-library` 随条目返关联 KP 聚合。AI 答疑发卡：`tutor/agent.py` 命中图库图形才 emit `interactive_scene`（反臆造，容错吞演示不吞正文）。（遗留两项已闭环：figures 改构建期生成 `frontend/scripts/gen_figures.py` + courseware 新建即补 `resolve_kp_scene`）。
- ⚠️ **同一实体有两份 schema**：`features/*/service.py`（助手查询工具投影）与 `router.py`+`schemas.py`（REST）。**前端打的是 REST**——只改 service 端点响应里连 key 都没有（ADR-0061 §U 翻车：题库 `scene_spec`/`semester`）。**「下发了 X」必须打到端点验**。
- **交互讲解读路径唯一入口 `scene_spec_for_read`**（ADR-0061 §U）= 快照 → 知识点+学期实时解析 → **图库兜底**（题面命中图库图形才出图，否则 None 不臆造；引导语不泄条数；optionGroup 时去 `outputs`）。四条读路径共用。

## 6. 题型模型（ADR-0004 D5，2026-10-05）
- **qtype 域**：`{choice,fill,calc,open}`（后端权威）。填空/计算/应用共用输入框；选择走选项卡。
- **多选**：新增 `multi:bool`（默认False），跨 10 个模型 + 启动期 ALTER；`TaskSpec.multi=True` 仅允许 `qtype=='choice'`（否422）。前端 `AppOptionTile.multi` 方块复选；提交 `(_selectedOptions..sort()).join('|')`；**评分按选项集合比对**（顺序无关/去重/空白忽略）。
- **判断题**：无独立类型，`choice`+对/错二选一（前端 `isJudgeQuestion` 识别）→ 复用单选卡、UI 标「判断题」。
- ⚠️ 选择题须带≥2有效选项，否则拦 `TASK_CHOICE_NO_OPTIONS(422)`（旧 choice+null 退化文本框 bug 已修）。
