# openedu · 项目长期约定

> 设计语言/令牌/原则：`.impeccable.md` + `docs/adr/0044–0060`；术语 `CONTEXT.md`；入口 `AGENTS.md`（细节在 `docs/agents/{architecture,frontend,ai}.md`）。
> 本文件只留**实测数字 / 归因 / 操作纪律**。⚠️ 注入上限 ~11.5k 字符，超出不可见：新增前先删等量旧话。

## 0. 环境 / 命令 / 多会话
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）。`flutter analyze` 退出码常非 0 → 认 `No issues found!`。⚠️ `flutter test` **必先关代理**（`env no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同值`，否则 `Invalid WebSocket upgrade request`），全量 ~16s。
- ⚠️ 禁跑 `dart format`（本机 tall style 版本不同 → 85/118 文件噪声 diff）；只靠 analyze。
- ⚠️ 多会话并行改共享文件（`app_theme.dart`/`MEMORY.md`/`AGENTS.md`/`.impeccable.md`）：先 `git status` + 看 mtime，定点 Edit，写完回读（本文件被并发整写覆盖过两次）。
- ⚠️ `flutter test` 慢先查游离进程：挂死探针占 `build/test_cache` 锁 → 等锁假失败（`ps | grep flutter_tester` → kill）。新增原生插件必须完整重跑 App（Hot Restart 不补原生注册 → pigeon `channel-error`）。
- ⚠️ 本机 `grep` 是 BSD 版，不支持 BRE 的 `\|` → `grep "a\|b"` **静默返回空**；一律 `grep -E`，且 `grep -c` 得 0 不等于没有（用 Grep 工具复核）。曾误判两次。zsh 下 `--include=*.dart` 要加引号。
- ⚠️ **新建 ADR 取号前查目录最大号 + `git status docs/adr/` + memory 预留**（撞车三次：0055、0058）。只看 `ls` 会漏掉别人**已建未提交**的文件。

## 1. 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider` + `AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。**助手路由优先级即功能**（ADR-0054）：写意图走 `guide`（`priority=20`）；不高于 `query`(12) 就被只读查询接走（query triggers 含泛词「任务/作业」）。📚 架构教材 `docs/learning/ai-assistant/`。
- **卡片动作是受控枚举**：`actions=[{label,target}]`，target 如 `parent_create_task`（**不是 URL**），前端 `ShellDestination.fromTarget` 解读、认不出即不动；**新增 target 两端同改**（`guide/agent.py` + `fromTarget`）。跨页导航走 `shared/presentation/shell_navigation.dart` → `HomeScreen` 的 `ref.listen`。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`；`App*` 只给 `shared/widgets/`；各 feature 有 repository、**刻意不建 datasource**。相对 import 越过 `lib/` 根时分析器不报错 → 层数自己数准。
- ⚠️ **非 push 路由的页面禁裸 `Navigator.pop`**：底下没有可弹的路由，弹的是根栈最后一条＝整个 App → 白屏（下次重建撞 `NavigatorState.build` 的 `_history.isNotEmpty`，热重启才炸）。走注入回调或 `maybePop`。

（守卫清单见 `docs/agents/frontend.md` §6）

## 2. 视觉与控件实测事实（取值见 `.impeccable.md`）
- 描边三档禁裸数字：2 `borderWidth`（卡/弹窗/浮层）· 1.5 `borderWidthSm`（chip/徽标/题号）· 1 `borderWidthHairline`（顶栏底边/侧栏右缘/分隔线/`listRow`）。
- ⚠️ **「白物体在纸底没边界」是头号陷阱**：`surfaceRaised` vs 纸底 `#FDFBF7` 仅差 ~1.02 → 补描边而非加粗；输入框刻意留 1px（`AppControl.inputStrut`，加粗裁字）。
- 空态统一 `AppEmptyState`（ADR-0051）。reduce-motion 须 `reducedMotionOf(context) ? Duration.zero : …`；浮层阴影统一 `_floatingShadows()`（暗色返 `none`），别写 `shadows: const []`。
- ⚠️ **`ShadButton.height` 是「内容盒高」**，描边画在盒**外** → 可见高 = 值 + 2×描边宽（声明 32 **实测 40**）；收口 `AppControl.buttonContentHeight()`；不可放进会压缩它的容器 → overflow；并排按钮一律 `Wrap`。图标按钮用 `AppIconAction`、行内文字操作用 `AppTextAction`（`CupertinoButton` 44×44 `minSize` 是第三种高度权威）。
- ⚠️ **`ShadCard` 比内容高时内容贴顶不居中**（卡 44/内容 28 → 上 1 下 15）→ 钉高的调用点自己包 `Center`。`Row(stretch)` 必须包 `IntrinsicHeight`；`Column(stretch)` 安全。**高度 = 触控锚点逐阶下推**：`heightLg`=48，标准 −`step`(8)，紧凑 −2×`step`；调档只改锚点（`AppControl`）。
- **语义色**：学科标记走 `SubjectMarkIcon`/`SubjectKey.mark`，**实际由 `_TagChip` 渲染**（`AppTags.subject` 私有组件内）——只读工厂函数就断言「零业务调用」是错的；助手卡 `AssistantCardHeader` 按类别上色（cyan=待办/复习、magenta=错题/掌握）。
- ⚠️ **`reducedMotionOf` 事实源在 `shared/theme/app_theme.dart`**（主题层也读它 → 反向 import 成循环）；别用 `export ... show` 转出（6 个调用点的 `app_motion` import 会变 `unnecessary_import`）。

## 3. 自适应布局（ADR-0045，令牌表见 `AppLayout`）
- `AdaptiveShell` 实为两档（ADR-0059 删了 `detail` 与双栏）：紧凑 <700 = 娃娃底栏/家长抽屉；≥700 = 侧栏 240↔64。`largeMin 1200` 无消费者。✅ 适配层实测完好（九档 × 两模式零溢出）——「没适配 device」类报障先怀疑「看不见」。
- ⚠️ **导航状态必须单一**（ADR-0059）：家长端「当前页面」只有 `sealed ParentPage`（`parent_pages.dart`），所有入口只调 `_go(page)`（`profile_screen.dart` 已删除，折为 `_Profile`）。并列状态 ⇒ 必然要「谁压谁」的裁决，散在各回调里必漏清，且 analyze 照不出来。⚠️ `_onProfileTap` 是两角色共用的，娃娃端仍走 `_showProfile`。
- ⚠️ **文件规模棘轮**（ADR-0058）：`test/file_size_guard_test.dart` 的 `_baseline` 只许下调，新文件 >400 行直接拦。**P0–P4 已全部执行完**（2026-09-21，见 `docs/refactor/…decomposition.md` §8），基线 14 → **11 条**（现最大：`parent_question_bank_view` 838 / `parent_tasks_view` 649 / `app_theme` 1695）。⚠️ ADR-0058 §8 那张基线表是立 ADR 当天的快照、已与代码不符——**事实源是测试里的 `_baseline`**。
- ⚠️ **拆大文件时先看两类「搬不动的东西」**：① **私有标识不跨 library**——`_ParentPage` + 11 个子类搬出 `home_screen` 就必须改公开（ADR-0059 的判据是「只有一个 `_parentPage` 字段」，与类名公开与否无关）；② **被多处共用的私有函数**（`assistant_cards` 的 `_s`/`_rowOf`/`_statsOf` 同时供渲染与「复制纯文本」用）→ 必须落到 domain 层（现 `features/assistant/domain/card_payload.dart`），留在 widget 文件里就只能复制一份并让它漂移。
- ✅ **桌面窗口地板 320×568**（修订 ADR-0045，推翻 800×600；旧值 800 > `compactMax` 700 使紧凑档从未渲染）：macOS/Windows/Linux 三处 runner 同改。⚠️ 六个平台目录从未进版本控制（`frontend/.gitignore:20–25`）→ 改完必须 `flutter build` 重跑。
- ⚠️ **内容兜底必须 `Align(topCenter)` + `ConstrainedBox`，不可 `Center`**。守卫 `test/adaptive_shell_layout_test.dart`。
- ⚠️ **`Navigator.push` 整页不在壳兜底内**：宽度走 `AppContentFrame`（全仓唯一出口，16 调用点/12 文件，守卫 `test/content_frame_guard_test.dart`）、退路走 `AppPushedPage`（`showBack` 默认 true）；别手写 `AppTopBar(showBack:)`（默认 `false` = 锁死一屏）。勿把「故意留在框外的兄弟节点」一起钉窄。
- ⚠️ **浮层宽度令牌指「外框宽」**：`popoverTheme.padding` + 2px 描边在内容**之外** → 内容侧须减 `popoverChrome`。（P3 已把主题层那 12 个 widget 整体搬到 `shared/widgets/`，`app_theme` 2740 → 1695。）

## 4. 测试与截图探针
- 五个「会挂死 / 量错」的坑（`runAsync` / `ShadApp.custom` 的 theme / pdfx / `pumpAndSettle` / MediaQuery 注入位置）已迁到 **`docs/agents/frontend.md` §7**，此处不重复。

## 5. Git / 后端 / 长列表
- ✅ `git push origin main` 可通；⚠️ 常输出 `Everything up-to-date` 但已成功 → 以 `git ls-remote origin main` 比对 HEAD 为准。提交按**逻辑批次**拆、正文写「为什么」；`chore(memory):` 单独提交。
- **引擎失败归因**：`decrypt()` 解不开只返 `None`（密文永不出门）；`ToolUnsupportedError`(无 FC) vs `ProviderRequestError`（带 `kind` + `user_hint`）落点 `genkit.py#classify_failure`；禁 `except Exception` 把引擎失败抹成「请添加模型」。
- 工具 schema strict（ADR-0040）：可省略参数要有缺席编码（`""`/`0`/枚举含 `NO_FILTER="all"`）。助手分流（ADR-0043）：`acc` 只收 TEXT。残留：`deepseek-v4-flash` 多轮 tool loop 退化成 XML → 对策**减跳数**。
- pytest 前 `cd backend && mv .env .env.hidden`（跑完恢复）；用 `.venv/bin/ruff`、`.venv/bin/pytest`（全量 ~25s）。偶发 `Sensitive content approval timed out` → 重跑。
- **「测试连接」**（2026-09-20，`POST /models/test` + `model_management/probe.py`）：① **必须走后端**（密钥密文只在后端）；② **与生产同源**——经 `app.ai.engine.build_engine` 构造，另起 HTTP 直连会造「测试过、出题挂」的假绿灯；③ 失败一律 200 + `ok=false`。超时 `MODEL_PROBE_TIMEOUT_S=20`。
- ⚠️ **探针「首帧即停」，绝不读完整个流**（qwen3:1.7b 带 thinking：一句 ping 要 6.4s 吐完 330 token，首 chunk <1s）。收尾两步：先 `future.cancel()`；再判 `future.done()` 后 await——401 时一帧都没有、channel 只静默 `StopAsyncIteration`，不 await 会把认证失败判成连接成功。
- **本地 Ollama 慢 ≠ 探针慢**：直连 curl 81ms vs 探针 16.8s，服务端日志证实 Ollama 真花了 16s——2.9GB 权重换入内存（切模型会挤掉上一个），同模型紧接着再测 0.67s。真实出题同样要付这个冷加载。
- **产品定位（2026-09-21 拍板）**：家庭自用为主 + 轻量开源（他人可自部署）；**已放弃跨家庭内容分享**（ADR-0019 版权红线对自用/自部署归零）。⚠️「开源给多人用」≠「内容跨家庭流通」。文档分工：**README 只放产品，技术内容在 `CONTRIBUTING.md`**。
- **学习闭环六段只有一段通**（详见 `2026-09-21.md` §业务拓展盘问）：仅「答错即建错题」通（`tasks/service.py:1236`）；出题**不消费**错题与掌握度（`question/pipeline.py:45-111` 零引用）。修法 ADR-0060：掌握度 → 显式出题入口 + 以代表错题（上限 3）仿写**同类题**；`Question` 无 origin 字段，仿写有版权遗留。
- **长列表（ADR-0053）**：keyset 游标（非 offset）；⚠️ 追加在途换条件会拼回旧页 → await 后重读最新 state；⚠️ 两列不用 `SliverGrid`（行高被钉死会裁卡）→ `Row`+`Expanded`（阈值 `listTwoColumnMin 1048`）；⚠️ 读错题每处都要加 `graduated_at IS NULL`；归档三套语义禁共用；迁移走启动期幂等 DDL，不引入 alembic。
