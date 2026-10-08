# openedu · 项目长期约定

> 权威设计/令牌/原则在 `.impeccable.md` + `docs/adr/0044–0073` + `docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。本文件只留**实测数字/归因/操作纪律**。⚠️ 注入上限 ~11.5k 字符，超则截断：新增前先删等量旧话。

## 0. 环境/命令/多会话
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）。`flutter test` **必先关代理**（`no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`，否则 `Invalid WebSocket upgrade request`），全量~16s。`flutter analyze` 退出码常非0 → 认 `No issues found!`。
- 禁 `dart format`（本机 tall style 不同 → 噪声 diff）；只靠 analyze。新增原生插件须完整重跑 App（Hot Restart 不补原生注册 → pigeon `channel-error`）；游离 `flutter_tester` 占 `build/test_cache` 锁 → kill。
- 多会话并行改共享文件：先看 `git status`+mtime，定点 Edit，写完回读（本文件被并发整写覆盖过两次）。
- 本机 `grep` BSD 版不支持 `a\|b` → `grep -E`；`grep -c` 得0≠没有，用 Grep 工具复核。
- 新 ADR 取号前查目录最大号 + `git status docs/adr/` + memory 预留（撞车三次 0055/0058）。
- SwiftPM 依赖解析走 libgit2：不读 `http_proxy`、不认 gitconfig `insteadOf`；唯一生效的是 SwiftPM mirror（`~/.swiftpm/configuration/mirrors.json` + 工程 `xcshareddata/swiftpm/configuration/mirrors.json`）。本地验证 `swift package resolve --disable-sandbox`。脚本 `frontend/scripts/patch_spm_cwl_mirror.py`（幂等+`--check`）。

## 1. 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。助手路由优先级即功能（ADR-0054）：写意图 `guide`(20) 高于只读 `query`(12)。
- 卡片动作受控枚举 `actions=[{label,target}]`（target 非 URL）；`ShellDestination.fromTarget` 解读，认不出即不动；新增 target 两端同改（`guide/agent.py`+`fromTarget`）。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`；各 feature 有 repository、不建 datasource。
- ⚠️ R4 棘轮：`presentation/` 不得 import `*/data/`（`test/feature_boundaries_test.dart`）。要用 data 类型 → 搬 `domain/repositories/`，data/ 只留 `Impl`。
- ⚠️ 非 push 路由页面禁裸 `Navigator.pop`（弹根栈=整个App→白屏）；走注入回调或 `maybePop`。

## 2. 视觉/控件实测
- ⚠️ 全仓禁用 Material 控件（`InkWell`/`Icons.`/`Scaffold`/`ListTile`/`Divider`/`Tooltip`）：根是 `ShadApp`+`CupertinoApp`，无 Material 祖先，构建期即抛「No Material widget found」且 analyze 照不出来 → 新控件测试须在不套 Material 的树里真构建（`test/assistant_sources_bar_test.dart` 先例）。可点区一律 `AppFocusableAction`。
- 描边三档：2/1.5/1（`borderWidth`/`borderWidthSm`/`borderWidthHairline`）。白物体在纸底 `#FDFBF7` 无边界（`surfaceRaised` 仅差~1.02）→ 补描边非加粗。
- 空态 `AppEmptyState`(ADR-0051)。reduce-motion 须 `reducedMotionOf(context)?Duration.zero:…`；浮层阴影 `_floatingShadows()`（暗色返 `none`）。
- ⚠️ `ShadButton.height` 是内容盒高，描边画盒外 → 可见高=值+2×描边宽（声明32**实测40**）；并排按钮一律 `Wrap`。图标按钮 `AppIconAction`、行内 `AppTextAction`。
- ⚠️ `ShadCard` 比内容高时内容贴顶不居中 → 钉高调用点自包 `Center`。`Row(stretch)` 须包 `IntrinsicHeight`（裸 stretch 在无限高上下文必崩，`stretch_row_guard_test` 守）；`Column(stretch)` 安全。
- `ReflectionSceneWidget` 画布边长=宽度正方形（ADR-0061 §O）：顶点由 `frontend/scripts/gen_figures.py` 构建期从后端 `materials/scene_figures.py` 生成，`figures.dart` 为 const 产物，parity 测试 `test_frontend_figures_are_not_stale` 钉住。
- 多图形不平铺（ADR-0061 §V）：`optionGroup` → 图形画廊（整库 11 卡片，列数按可用宽度、目标卡宽 124 夹 2–6 列）+ 弹 `ReflectionSceneDialog`。弹窗画布边长按屏高夹 `min(420, 屏高−320, 屏宽−64)` 再夹 [220,420]。画廊只画不判。
- `reducedMotionOf` 事实源在 `shared/theme/app_theme.dart`；别 `export … show` 转出。

## 3. 自适应布局（ADR-0045/0059）
- `AdaptiveShell` 两档：紧凑<700=娃娃底栏/家长抽屉；≥700=侧栏240↔64。`largeMin 1200` 无消费者。
- ⚠️ 导航状态必须单一：`sealed ParentPage`/`TeacherPage`，所有入口只调 `_go(page)`；并列状态⇒必漏清且 analyze 照不出。
- ⚠️ 文件规模棘轮（ADR-0058）：`test/file_size_guard_test.dart` 的 `_baseline` 只许下调，新文件>400行直拦；搬代码块禁用正则删方法（DOTALL `.*?` 会跨吞下一方法 body → 逐行原样搬）。`AppTheme.colorsOf(context)` 返 `AppColors`。
- 桌面窗口地板 320×568；六平台目录未进版本控制 → 改完须 `flutter build`。
- 内容兜底须 `Align(topCenter)`+`ConstrainedBox`，不可 `Center`。`Navigator.push` 整页走 `AppContentFrame`+退路 `AppPushedPage`(`showBack`默认true)；勿手写 `AppTopBar(showBack:)`。浮层宽令牌指外框宽，内容侧减 `popoverChrome`。

## 4. 测试/截图探针
- 五坑（`runAsync`/`ShadApp.custom` theme/pdfx/`pumpAndSettle`/MediaQuery 注入位）见 `docs/agents/frontend.md` §7。
- ⚠️ `ShadApp.custom(appBuilder:)` 不装 `ShadToaster` → widget 测试用 appBuilder 须显式 `ShadToaster(child:)`，否则 `AppToast.show` 抛「Could not find ShadToaster」。
- 测试里改 `debugDefaultTargetPlatformOverride` 在 tearDown 复位不及 → 别改平台；长按用 `startGesture`+`pump(kLongPressTimeout)`，点按把 `holdToTalk` 显式传进组件。

## 5. Git/后端/长列表
- 平台目录不在版本控制 → 打补丁脚本（`frontend/scripts/patch_macos_network.py` 网络、`patch_voice_permissions.py` 语音 ADR-0063 §10），幂等+`--check`。macOS 沙盒麦克风需 entitlements `com.apple.security.device.audio-input`。常显 `Everything up-to-date` 却已成功 → 以 `git ls-remote origin main` 比对 HEAD。提交按逻辑批次拆、正文写「为什么」；`chore(memory):` 单独提交。
- ⚠️ `git commit -- <file>` 会重暂存该文件整个工作区 → hunk 级拆分须 `git add -p` 后**不带 pathspec** `git commit`。
- 引擎失败归因：`decrypt()` 解不开只返 `None`；`ToolUnsupportedError` vs `ProviderRequestError`(`kind`+`user_hint`) 落 `genkit.py#classify_failure`；禁 `except Exception` 抹成「请添加模型」。
- ⚠️ 可空 JSON 列须 `JSON(none_as_null=True)`（ADR-0061 §N/§T），否则 `None` 序列化成文本 `'null'` → `IS NOT NULL` 为真而内容空。已全仓统一（12 列）。存量迁移 `_nullify_text_json_nulls`。
- ⚠️ 选项标号只由渲染层画且必须同时剥模型前缀（ADR-0061 §T）：后端 `normalize_options` 刻意不剥（答案也带前缀）→ 前端每处选项渲染过 `cleanOptionText`。守卫 `tests/ai/test_option_prefix_contract.py`。
- ⚠️ SQLite「加列」≠「加约束」（ADR-0061 §R）：`ADD COLUMN` 里的 `UNIQUE` 被静默忽略 → 老库仍留旧约束而新建库正常。改 UNIQUE 须重建表（幂等，先读 `sqlite_master`）。
- pytest 前 `cd backend && mv .env .env.hidden`（完恢复）；`.venv/bin/ruff`/`.venv/bin/pytest`（全量~25s）。沙盒里必须 `--basetemp=/tmp/<新目录>`，否则 `tmp_path` 集体 PermissionError。真库 `backend/app.db`（相对 backend）→ 必先 `cd backend`。既存顺序污染失败 4 个（vectorize/retrieval 3 + `test_confirm_flips_all_semester_variants`），干净树全量同败、单跑过。
- 「测试连接」走后端+`build_engine` 同源；失败 200+`ok=false`；超时 `MODEL_PROBE_TIMEOUT_S=20`。探针首帧即停：`cancel()` 后判 `done()` 再 await（401 时一帧无、channel 静默 `StopAsyncIteration`）。
- 本地 Ollama 慢≠探针慢（切模型权重换入内存真花~16s）。
- 「AI 编造数据」≠越权：先查 message 轨迹有无 `tool_call`/`tool_result`（有必落库）；无=模型编。流式改 FC：`ministral-3:3b` `stream=true` 零 tool_calls 编正文、`stream=false` 正确返回；`qwen3:1.7b` 流式正常。
- 学习闭环六段只一段通：仅「答错即建错题」(`tasks/service.py:1236`)；出题不消费错题/掌握度。修法 ADR-0060。
- 长列表(ADR-0053)：keyset 游标；追加在途换条件会拼回旧页→await 后重读；读错题加 `graduated_at IS NULL`；迁移走启动期幂等 DDL。
- ⚠️ 分层不变量9：归属判定只许走 `core.guard`(`require_owned`/`find_owned`/`require_owned_child`)，禁内联 `x.parent_id!=y`；AST 守卫 `tests/ai/test_layering_invariants.py`。改 `features/*/service.py` 必跑 `tests/ai/`。
- ADR-0064 多选删除：`POST /materials/bulk-delete`+`/materials/knowledge-points/bulk-delete`。删资料的知识点连带=只删孤儿（同 `(subject,grade,semester,name)`+无其他留存资料引用+`source=emerged && status=pending`）。KP↔Material 无外键、只靠名字串。
- ADR-0055 资料库+RAG：4表全带 parent_id；向量存 BLOB 暴力扫；dense+sparse+RRF(BGE-M3)。`EMBEDDING_MODEL` 兼向量版本戳。`build_retriever(session,parent_id)` 新签名。
- ⚠️ ADR-0073 场景库：`KnowledgePoint.scenes` 是唯一事实源；后端 `SCENE_LIBRARY` 仅作者辅助，渲染/生成永不回查；无 `scene_name` 列，kind 取 `scenes[].kind]`；`figure` 绝不预填；`get_builtin_scene` 必返深拷贝；统一入口 `resolve_kp_scene`。AI 答疑命中图库图形才 emit `interactive_scene`。
- ⚠️ 同一实体两份 schema：`features/*/service.py`（助手工具投影）与 `router.py`+`schemas.py`（REST）。前端打 REST——「下发了 X」必须打到端点验。交互讲解读路径唯一入口 `scene_spec_for_read`（ADR-0061 §U）= 快照→知识点+学期实时解析→图库兜底。

## 6. 题型模型（ADR-0004 D5）
- qtype 域 `{choice,fill,calc,open}`（后端权威）。填空/计算/应用共用输入框；选择走选项卡。
- 多选 `multi:bool`（默认False），跨 10 模型+启动期 ALTER；`TaskSpec.multi=True` 仅允许 `qtype=='choice'`（否422）。前端 `AppOptionTile.multi` 方块复选；提交 `(_selectedOptions..sort()).join('|')`；评分按选项集合比对（顺序无关/去重/空白忽略）。
- 判断题：无独立类型，`choice`+对/错二选一（前端 `isJudgeQuestion`）→ 复用单选卡、UI 标「判断题」。
- 选择题须带≥2有效选项，否则拦 `TASK_CHOICE_NO_OPTIONS(422)`。
