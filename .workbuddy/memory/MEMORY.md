# openedu · 项目长期约定

> 设计语言/令牌/原则：`.impeccable.md` + `docs/adr/0044–0054`（已写清的不重复）；术语 `CONTEXT.md`。
> 本文件只留**实测数字 / 归因 / 操作纪律**。⚠️ 有**注入上限 ~11.5k 字符**，超出部分对后续会话不可见：新增事实前先删等量旧话。

## 0. 环境 / 命令 / 多会话
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）。`flutter analyze` 退出码常非 0 → 认 `No issues found!`（~100s，放后台）。`flutter test` 必先关代理：`env no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同值 <sdk>/bin/flutter test`（否则 `Invalid WebSocket upgrade request`），全量 ~16s。
- ⚠️ **禁跑 `dart format`**（本机 tall style 版本不同 → 85/118 文件噪声 diff）；只靠 analyze。
- ⚠️ **多会话并行改共享文件**（`app_theme.dart`/`MEMORY.md`/`AGENTS.md`/`.impeccable.md`）：先 `git status` + 看 mtime，**定点 Edit**，写完回读（本文件被并发整写覆盖过两次）。
- ⚠️ **`flutter test` 异常慢先查游离进程**：挂死探针占 `build/test_cache` 锁 → 等锁假失败（`ps | grep flutter_tester` → kill）。**新增原生插件必须完整重跑 App**（Hot Restart 不补原生注册 → pigeon `channel-error`；判据：进程启动时间 vs `pubspec.lock` mtime）。
- ⚠️ **本机 `grep` 是 BSD 版，不支持 BRE 的 `\|`** → `grep "a\|b"` **静默返回空**，像「文件里没有」；一律 `grep -E`，且 **`grep -c` 得 0 不等于没有**（用 Grep 工具复核）。曾误判两次。zsh 下 `--include=*.dart` 要加引号否则 glob 报错。

## 1. 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider` + `AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。业务字段不前端预填。
- **助手路由优先级即功能**（ADR-0054）：写意图走 `guide`（`priority=20`，无工具/不调模型）；**不高于 `query`(12) 就被只读查询接走**（query triggers 含泛词「任务/作业」）。守卫 `tests/ai/test_guide_subagent.py`。
- **卡片动作是受控枚举**：`actions=[{label,target}]`，target 如 `parent_create_task`（**不是 URL**），前端 `ShellDestination.fromTarget` 解读、认不出即不动；**新增 target 两端同改**（`guide/agent.py` + `fromTarget`），否则按钮「点了没反应」。跨页导航走 `shared/presentation/shell_navigation.dart` → `HomeScreen` 的 `ref.listen` → `_parentTap(index)`。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`；`App*` 只给 `shared/widgets/`；各 feature 有 repository、**刻意不建 datasource**。features 可 import `app.ai`。相对 import 越过 `lib/` 根时分析器不报错 → 层数自己数准。守卫 `test/feature_boundaries_test.dart`。

## 2. 视觉与控件实测事实（取值见 `.impeccable.md`）
- 描边三档禁裸数字：2 `borderWidth`（卡/弹窗/浮层）· 1.5 `borderWidthSm`（chip/徽标/题号）· 1 `borderWidthHairline`（顶栏底边/侧栏右缘/分隔线/`listRow`）。
- ⚠️ **「白物体在纸底没边界」是头号陷阱**：`surfaceRaised` vs 纸底 `#FDFBF7` 仅差 ~1.02 → **补描边而非加粗**；**输入框刻意留 1px**（耦合 `AppControl.inputStrut`，加粗裁字）。
- 空态统一 `AppEmptyState`（ADR-0051）。**reduce-motion** 须 `reducedMotionOf(context) ? Duration.zero : …`；浮层阴影统一 `_floatingShadows()`（暗色返 `none`），别写 `shadows: const []`。
- **高度 = 触控锚点逐阶下推**：`heightLg`=48；标准 −`step`(8)；紧凑 −2×`step`。调档只改锚点（`AppControl`）。
- ⚠️ **`ShadButton.height` 是「内容盒高」**，描边画在盒**外** → 可见高 = 值 + 2×描边宽（声明 32 **实测 40**）；收口 `AppControl.buttonContentHeight()`，守卫 `test/control_height_test.dart`；**不可放进会压缩它的容器**（`Expanded`/固定宽）→ overflow；并排按钮一律 `Wrap`。图标按钮用 `AppIconAction`、行内文字操作用 `AppTextAction`（`CupertinoButton` 的 44×44 `minSize` 是第三种高度权威）。
- ⚠️ **`ShadCard` 比内容高时内容贴顶不居中**（卡 44/内容 28 → 上 1 下 15）→ 钉高的调用点自己包 `Center`。**`Row(stretch)` 必须包 `IntrinsicHeight`**（否则无界高父级抛 infinite height）；`Column(stretch)` 安全。
- **语义色**：学科标记走 `SubjectMarkIcon`/`SubjectKey.mark`，**实际由 `_TagChip` 渲染**（`AppTags.subject` 私有组件内）——**只读工厂函数就断言「零业务调用」是错的**；助手卡 `_CardHeader` 按类别上色（cyan=待办/复习、magenta=错题/掌握），前景走 `AppBrutal.onColor`。
- ⚠️ **`reducedMotionOf` 事实源在 `shared/theme/app_theme.dart`**（主题层也读它 → 反向 import 成循环）；**别用 `export ... show` 转出**（会让 6 个调用点的 `app_motion` import 变 `unnecessary_import`）。

## 3. 自适应布局（ADR-0045，令牌表见 `AppLayout`）
- `AdaptiveShell` 三档：紧凑 700 = 娃娃底栏 / 家长汉堡抽屉；中屏 = 侧栏单栏；≥1200 有 `detail`。✅ 适配层实测完好（九档 × 两模式零溢出，守卫 `test/device_size_fit_test.dart`）——**「没适配 device」类报障先怀疑「看不见」**。
- ✅ **桌面窗口地板 320×568**（修订 ADR-0045，推翻 800×600；旧值 800 > `compactMax` 700 使紧凑档从未渲染）：三处同改 macOS `MainFlutterWindow.swift` / Windows `runner/main.cpp` / Linux `my_application.cc`。⚠️ **六个平台目录从未进版本控制**（`frontend/.gitignore:20–25`）→ 配置 git 里查不到，**改完必须 `flutter build` 重跑**。本机只有 macOS + Chrome。
- ⚠️ **内容兜底必须 `Align(topCenter)` + `ConstrainedBox`，不可 `Center`**（否则不足一屏的页面浮到屏中）。守卫 `test/adaptive_shell_layout_test.dart`。
- ⚠️ **`Navigator.push` 整页不在壳兜底内**：宽度走 `AppContentFrame`（全仓唯一出口，守卫 `test/content_frame_guard_test.dart`）、退路走 `AppPushedPage`（`showBack` 默认 true）；别手写 `AppTopBar(showBack:)`（默认 `false` + 桌面无返回手势 = 锁死一屏）。`alignment` 照抄原值；勿把「故意留在框外的兄弟节点」（`practice_review_view` 通栏行动条）一起钉窄。
- ⚠️ **浮层宽度令牌指「外框宽」**：`popoverTheme.padding` + 2px 描边在内容**之外** → 内容侧须减 `popoverChrome`（写 224 得 244）。`AppFocusableAction` **定义在 app_theme.dart**（放 shared/widgets 成循环）。

## 4. 测试与截图探针（多为「像 bug 实为测试替身假象」）
- ⚠️ **`toImage()` 与 `FontLoader` 前的 `readAsBytes()` 必须包 `tester.runAsync`**，否则 fake-async 区 await 永不返回 → 挂死 exit 137。真字形需 `assets/fonts/{Inter,NotoSansSC}.ttf`。
- ⚠️ **`ShadApp.custom` 不传 `theme:` 走 shadcn 默认主题** → 量到数与产品不符；看视觉/几何必传 `AppTheme.shadFor(false, mode, density)`。**`SizedBox(width: 2000)` 给不了 2000px 视口**（surface 默认 800×600 会裁 → 断点静默测错档）→ 用 `setSurfaceSize` + `addTearDown`。
- ⚠️ **别直接调 pdfx `PdfDocument.openData`**：无原生一侧时 Future **既不完成也不报错** → `flutter_tester` 挂死，走 `pdfDocumentOpenerProvider` 注替身；**catch 掉的异常也要 `debugPrint` 留痕**。
- ⚠️ **`pumpAndSettle` 只按「还有没有下一帧」推进**：悬挂 `Timer` 不排帧 → 须显式 `pump(delay)`；**含不确定态 spinner 的子树必然超时**。`AnimatedSwitcher` 退场在「整档时长 + 一帧」才摘节点 → 推**两档时长**。
- ⚠️ **`pumpWidget` 根之上没有 MediaQuery 祖先** → 注入 reduce-motion 要把 `MediaQuery` 放在 `CupertinoApp`/`ShadApp` **之内**；直接给 `MediaQueryData(disableAnimations: true)` 会把 size 变 `Size.zero`。

## 5. Git / 后端 / 长列表
- ✅ `git push origin main` 可通；⚠️ 常输出 `Everything up-to-date` 但已成功 → 以 `git ls-remote origin main` 比对 HEAD 为准。提交按**逻辑批次**拆、正文写「为什么」；`chore(memory):` 单独提交；`backend/.agents/` 未跟踪。
- **引擎失败归因**：`decrypt()` 解不开只返 `None`（**密文永不出门**）；`ToolUnsupportedError`(无 FC) vs `ProviderRequestError`(厂商拒绝，带 `kind` + `user_hint`) 落点 `agent_core/adapters/genkit.py#classify_failure`；禁 `except Exception` 把引擎失败抹成「请添加模型」。
- 工具 schema strict（ADR-0040）：可省略参数要有缺席编码（`""`/`0`/枚举含 `NO_FILTER="all"`）。助手分流（ADR-0043）：`acc` 只收 TEXT。残留：`deepseek-v4-flash` 多轮 tool loop 退化成 XML → 对策**减跳数**。
- pytest 前 `cd backend && mv .env .env.hidden`（跑完恢复）；用 `.venv/bin/ruff`、`.venv/bin/pytest`（全量 ~25s）。偶发 `Sensitive content approval timed out` → 重跑。`Resource<T>` 迁移未完成。
- **「测试连接」（2026-09-20）**：`POST /models/test` + `app/features/model_management/probe.py`。① **必须走后端**（密钥密文只在后端，编辑态「密钥留空=不修改」只有后端能补）；② **与生产同源**——经 `app.ai.engine.build_engine`（原私有 `_get_or_build` 改公开）构造，另起 HTTP 直连会造「测试过、出题挂」的假绿灯；③ **失败一律 200 + `ok=false`**，`error_kind` 沿用 ADR-0038 枚举 + `timeout`，detail 回显前抹密钥明文。超时 `MODEL_PROBE_TIMEOUT_S=20`（前端 Dio `receiveTimeout=30`，须留余量）。守卫 `tests/api/routes/test_model_probe.py`。
- ⚠️ **探针必须「首帧即停」，绝不读完整个流**（实测 `qwen3:1.7b` 带 thinking：一句「ping」要 **6.4s** 才把 330 token 思维链+回答吐完，首个 chunk 却 <1s；读完整个流 = 把一次握手做成一次完整生成，还会吃掉 20s 超时、报出「连接超时」假阴性）。收尾两步缺一不可：先 `future.cancel()`（genkit 已把生成派发成后台 task，撒手会留悬挂流）；再**判 `future.done()` 后 await**——401 时一帧都没有、channel 只静默 `StopAsyncIteration`，不 await 就变成「认证失败被判成连接成功」。
- **本地 Ollama 慢 ≠ 探针慢**（实测归因）：同一模型直连 curl 只要 **81ms**，探针却 16.8s；服务端日志（GIN）证实 Ollama **真的**花了 16s——那是把 2.9GB 权重**换入内存**（连续切模型会挤掉上一个：qwen3 1.35GB + ministral 2.9GB），同一模型紧接着再测 **0.67s**。SDK 请求参数很干净（`options:{}`，无 `num_ctx`/`keep_alive`），别去怪 genkit。结论：**真实出题同样要付这个冷加载**，不是探针独有；20s 超时对 7B+ 偏紧 → 超时文案按 provider 分化，ollama 提示「首次调用要加载权重，第二次通常很快」。
- **长列表（ADR-0053）**：keyset 游标（非 offset）；⚠️ 追加在途换条件会拼回旧页 → await 后重读最新 state；⚠️ 两列不用 `SliverGrid`（行高被钉死会裁卡）→ `Row`+`Expanded`，阈值 `listTwoColumnMin 1048`；⚠️ 读错题每处都要加 `graduated_at IS NULL`；归档三套语义禁共用；迁移走启动期幂等 DDL，不引入 alembic。

## 6. AI Agent 架构学习教材
- 📚 `docs/learning/ai-assistant/`（`lessons/0001-0003` + `reference/cheatsheet.html`）；四栏格式：**架构优点 / 当时决策(ADR) / 同类主流实现 / 代价遗留**。路由优先级即功能：`guide`20 > `query`12 > `question`0 > `tutor`-10。
