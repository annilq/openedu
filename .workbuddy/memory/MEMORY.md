# openedu · 项目长期约定

> 权威设计/令牌在 `.impeccable.md` + `docs/adr/` + `docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。本文件只留实测数字/归因/操作纪律。注入上限~11.5k，超则截断：新增前先删等量旧话。

## 0. 环境/命令/多会话
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）。`flutter test` 必先关代理（`no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`，否则 WebSocket 升级失败），全量~16s。`flutter analyze` 退出码常非0 → 认 `No issues found!`。
- 禁 `dart format`（本机 tall style 不同 → 噪声 diff）；只靠 analyze。新增原生插件须完整重跑 App（Hot Restart 不补原生注册 → pigeon channel-error）；游离 flutter_tester 占 build/test_cache 锁 → kill。
- 多会话并行改共享文件：先看 `git status`+mtime，定点 Edit，写完回读（本文件被并发整写覆盖过两次）。
- ⚠️ 并行 worktree 配方：`git worktree add /tmp/oedu-tXX -b ticket/XX <base>` + `ln -s <主仓>/backend/.venv` 与 `.env`；pytest 必须 `PYTHONPATH=/private/tmp/oedu-tXX/backend`。配 `mv .env .env.hidden`+`--basetemp=/tmp/<新>`。前端 worktree 可直接 `flutter test`。
- 本机 `grep` BSD 版不支持 `a\|b` → `grep -E`；`grep -c` 得0≠没有，用 Grep 工具复核。
- ⚠️ 本机 `/bin/bash`=3.2：`$VAR` 紧跟中文会吞多字节首字节→unbound variable，变量引用一律 `${VAR}`；脚本被 zsh 调需 `exec bash "$0" "$@"`。
- ⚠️ 本机实测(macOS 26)：`screencapture -v` 拒 `-i`（改 `-J video`）；窗口 ID 走 `swift -e`+CGWindowList。`flutter run -d macos` 产物名随工程变。
- ⚠️ 演示成片管线(`submission_docs/`)：时间轴取实测(ffprobe)。坑：`tpad`定格补帧必在`fps`之后；libass FontSize 非像素(无 PlayRes 的 SRT 按 288 基准≈×画面高/288)。
- 新 ADR 取号前查目录最大号 + `git status docs/adr/` + memory 预留（撞过 0055/0058）。
- 文案纪律：统一写「中小学」不写 K12；本项目「中小学」=1–9 年级(义务教育，不含高中)。替换后必查残留中英空格。
- 提交材料 docx 由 `submission_docs/gen.py` 生成。⚠️ python-docx 默认 Letter 纸(可用宽仅 15.24cm)→表格列宽超值溢出用 `set_col_widths` 钉住；run 不继承正文样式须显式 `set_run_font`。本机无 LibreOffice → 只程序化校验。

## 1. 前端分层(ADR-0036/0037)
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。路由优先级即功能(ADR-0054)：写意图 `guide`(20)>只读 `query`(12)。
- 卡片动作 `actions=[{label,target}]`(target 非 URL)；`ShellDestination.fromTarget` 解读。新增 target 两端同改。
- ⚠️ 结构化动作键 = manifest `actions` 等值匹配(ADR-0081)：`task_generate`/`quiz_generate`/`courseware_generate`/`courseware_hint`/`quiz_judge`。⚠️ 服务端「重生成」全删(ADR-0084)：出题唯一路径=`POST /tasks/generate`(流式)+`/tasks/from-generated`(落库)；`Task.specs` 仅审核页摘要。
- ⚠️ 课件内容纯手动编排(ADR-0085)：`POST /courseware` 恒建零环节空壳→编辑器「添加环节」→`PUT /sections`。课堂练习环节的 AI 出题/提示(原 `SectionPractice`)已端到端删除(ADR-0086)；保留的「课件里用 AI」仅剩讲课现场「问 AI 老师」浮标，走 `courseware_generate`/`courseware_hint`/`quiz_judge`+`AssistantChatReq.courseware`。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`。
- ⚠️ R4 棘轮：`presentation/` 不得 import `*/data/`(`test/feature_boundaries_test.dart`)。要用 data 类型→搬 `domain/repositories/`。
- ⚠️ 非 push 路由页面禁裸 `Navigator.pop`（弹根栈=白屏）；走注入回调或 `maybePop`。

## 2. 视觉/控件实测
- ⚠️ 全仓禁用 Material 控件(`InkWell`/`Icons.`/`Scaffold`/`ListTile`/`Divider`/`Tooltip`)：根 `ShadApp`+`CupertinoApp` 无 Material 祖先→构建期抛「No Material widget found」且 analyze 照不出。可点区一律 `AppFocusableAction`。
- 描边三档：2/1.5/1(`borderWidth`/`borderWidthSm`/`borderWidthHairline`)。白物体纸底 `#FDFBF7` 无边界→补描边非加粗。
- 空态 `AppEmptyState`(ADR-0051)。reduce-motion 须 `reducedMotionOf(context)?Duration.zero:…`；浮层阴影 `_floatingShadows()`(暗色返 none)。
- ⚠️ `ShadButton.height` 是内容盒高，描边画盒外→可见高=值+2×描边宽(声明32实测40)；并排按钮一律 `Wrap`。图标按钮 `AppIconAction`、行内 `AppTextAction`。
- ⚠️ `ShadCard` 比内容高时内容贴顶不居中→钉高调用点自包 `Center`。`Row(stretch)` 须包 `IntrinsicHeight`（裸 stretch 在无限高上下文必崩，`stretch_row_guard_test` 守）；**但子树含 `LayoutBuilder`(如 `SceneInterpreter`)时 `IntrinsicHeight` 也崩**——改用不依赖 intrinsic 的布局。**但色条也绝不能画成非均匀 `Border` 喂给 `ShadCard`/`AppCard`**：`ShadCard` 内部 `BoxDecoration(borderRadius)` 要求四边同色，非均匀边必抛 `A borderRadius can only be given on borders with uniform colors`(card.dart:206)。正确做法=`Stack`+左侧 `Container` 色条+靠卡片自身 clip 裁圆角(`wrong_questions_screen.dart` 先例)。`Column(stretch)` 安全。
- ⚠️ ADR-0083：几何单源在 `figure_library` 表(`BUILTIN_FIGURE_SEED` 仅播种，无 axis 字段)；`gen_figures.py`+parity 锁已退役，`figures.dart` 只剩 `FigureShape`+`kFallbackFigure`+`figureMatchingVertices`。SceneSpec=`{kind,points,edges}` 内联几何，运行时零图库依赖；轴初值归 kind 外壳(`scene_shells.dart`)，展示开关 `SceneInterpreter.showAxisControls`。
- 多图形不平铺(ADR-0061 §V/ADR-0083)：`optionGroup`→图形画廊(条目顺序即渲染顺序；卡宽 124 夹 2–6 列)+弹 `ReflectionSceneDialog`。弹窗画布边长夹 `min(420,屏高−320,屏宽−64)` 再夹[220,420]。画廊只画不判。

## 3. 自适应布局(ADR-0045/0059)
- `AdaptiveShell` 两档：紧凑<700=娃娃底栏/家长抽屉；≥700=侧栏240↔64。`largeMin 1200` 无消费者。
- ⚠️ 导航状态必须单一：`sealed ParentPage`/`TeacherPage`，所有入口只调 `_go(page)`；并列状态⇒必漏清且 analyze 照不出。
- ⚠️ 文件规模棘轮(ADR-0058)：`test/file_size_guard_test.dart` 的 `_baseline` 只许下调，新文件>400行直拦；搬代码块禁用正则删方法(DOTALL 跨吞方法 body→逐行原样搬)。`AppTheme.colorsOf(context)` 返 `AppColors`。
- 内容兜底须 `Align(topCenter)`+`ConstrainedBox`，不可 `Center`。`Navigator.push` 整页走 `AppContentFrame`+退路 `AppPushedPage`(`showBack`默认true)；勿手写 `AppTopBar(showBack:)`。浮层宽令牌指外框宽，内容侧减 `popoverChrome`。

## 4. 测试/截图探针
- ⚠️ `ShadApp.custom(appBuilder:)` 不装 `ShadToaster`→widget 测试用 appBuilder 须显式 `ShadToaster(child:)`，否则 `AppToast.show` 抛「Could not find ShadToaster」。
- ⚠️ 禁止在 `test/` 写截图装置：`RenderRepaintBoundary.toImage()` 在无真实合成器永不完成，实测把 `flutter test` 从~46s 堵到 17min。目检结论改几何断言(`getSize`/字段比对)，先例 `test/workbench_charts_layout_test.dart`。
- 网络层加接口同步 4 个测试替身(`assistant_api_client_test`/`list_archive_test`/`review_notifier_test`/`students_notifier_test`)，漏一个整条 test 编译不过。
- 测试里改 `debugDefaultTargetPlatformOverride` 在 tearDown 复位不及→别改平台；长按 `startGesture`+`pump(kLongPressTimeout)`，点按把 `holdToTalk` 显式传进组件。
- ⚠️ 静态护栏误报比漏报更坑：子串匹配一律词边界锚定(`contains('BarChart(')` 被 `AppBarChart(` 骗到，`2c7a320` 修)；import 探测引号不敏感。

## 5. Git/后端/长列表
- 平台目录不在版本控制→打补丁脚本(`patch_macos_network.py`/`patch_voice_permissions.py`)，幂等+`--check`。macOS 麦克风需 entitlements `com.apple.security.device.audio-input`。常显 `Everything up-to-date` 却已成功→以 `git ls-remote origin main` 比对 HEAD。提交按逻辑批次拆、正文写「为什么」；`chore(memory):` 单独提交。
- ⚠️ `git commit -- <file>` 重暂存该文件整个工作区→hunk 级拆分须 `git add -p` 后不带 pathspec `git commit`。
- 判「守卫失败本轮引入 or 既存」：`git worktree add /tmp/oedu-head HEAD`→那边 `flutter test <守卫文件>`(~10s)。先跑基线再归因、别照抄旧记忆(`a47c53e` 的「5 条红」到 `2c7a320` 已全消)。
- 引擎失败归因：`decrypt()` 解不开只返 None；`ToolUnsupportedError` vs `ProviderRequestError(kind+user_hint)` 落 `genkit.py#classify_failure`；禁 `except Exception` 抹成「请添加模型」。
- ⚠️ 可空 JSON 列须 `JSON(none_as_null=True)`(ADR-0061 §N/§T)，否则 None 序列化成文本 'null'→`IS NOT NULL` 为真而内容空。存量迁移 `_nullify_text_json_nulls`。
- ⚠️ 选项标号只由渲染层画且必须同时剥模型前缀(ADR-0061 §T)：后端 `normalize_options` 刻意不剥(答案也带前缀)→前端每处选项渲染过 `cleanOptionText`。
- ⚠️ SQLite「加列」≠「加约束」(ADR-0061 §R)：`ADD COLUMN` 里的 UNIQUE 被静默忽略→改 UNIQUE 须重建表(幂等，先读 `sqlite_master`)。
- pytest 前 `cd backend && mv .env .env.hidden`；`.venv/bin/ruff`/`.venv/bin/pytest`(全量~25s)。沙盒必 `--basetemp=/tmp/<新>`；真库 `backend/app.db`→必先 `cd backend`。
- 「AI 编造数据」≠越权：先查 message 轨迹有无 tool_call/tool_result(有必落库)；无=模型编。
- 学习闭环六段只一段通：仅「答错即建错题」(`tasks/service.py:1236`)；出题不消费错题/掌握度。修法 ADR-0060。
- 长列表(ADR-0053)：keyset 游标；追加在途换条件会拼回旧页→await 后重读；读错题加 `graduated_at IS NULL`；迁移走启动期幂等 DDL。
- ⚠️ 分层不变量9：归属判定只许走 `core.guard`(`require_owned`/`find_owned`/`require_owned_child`)，禁内联 `x.parent_id!=y`；AST 守卫 `tests/ai/test_layering_invariants.py`。改 `features/*/service.py` 必跑 `tests/ai/`。
- ADR-0064 多选删除：`POST /materials/bulk-delete`+`/materials/knowledge-points/bulk-delete`。删资料的知识点连带=只删孤儿(同 `(subject,grade,semester,name)`+无其他留存资料引用+`source=emerged && status=pending`)。
- ADR-0055 资料库+RAG：4表全带 parent_id；向量 BLOB 暴力扫；dense+sparse+RRF(BGE-M3)。`EMBEDDING_MODEL` 兼向量版本戳。`build_retriever(session,parent_id)` 新签名。
- ⚠️ ADR-0073 场景库：`KnowledgePoint.scenes` 唯一事实源；后端 `SCENE_LIBRARY` 仅作者辅助，渲染/生成永不回查；无 `scene_name` 列；`figure` 绝不预填；`get_builtin_scene` 必返深拷贝；统一入口 `resolve_kp_scene`。AI 答疑命中图库图形才 emit `interactive_scene`。
- ⚠️ 同一实体两份 schema：`features/*/service.py`(助手工具投影)与 `router.py`+`schemas.py`(REST)。前端打 REST——「下发了 X」必须打到端点验。交互讲解读路径唯一入口 `scene_spec_for_read`(ADR-0061 §U)。

## 6. 题型模型(ADR-0004 D5)
- qtype 域 `{choice,fill,calc,open}`。填空/计算/应用共用输入框；选择走选项卡。
- 多选 `multi:bool`(默认False)；`TaskSpec.multi=True` 仅允许 `qtype=='choice'`(否422)。前端 `AppOptionTile.multi` 方块复选；提交 `(_selectedOptions..sort()).join('|')`；评分按选项集合比对。
- 判断题：无独立类型，`choice`+对/错二选一(前端 `isJudgeQuestion`)→复用单选卡、UI 标「判断题」。
- 选择题须带≥2有效选项，否则拦 `TASK_CHOICE_NO_OPTIONS(422)`。
