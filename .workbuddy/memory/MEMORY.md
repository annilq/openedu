# openedu · 项目长期约定

## 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`（家长悬浮球 / 娃娃整页）；后端唯一端点 `POST /api/v1/assistant/chat`。业务字段不前端预填（subject 后端算、grade 取 JWT）。
- 单向 `main/ → features/* → shared/*`；`shared/` 不得 import `features/`；`App*` 只给 `shared/widgets/`。
- 9 feature 全有 repository（`domain/repositories` 接口 + `data/repositories/*_impl` + `features/<f>/providers/` 组合根）；**刻意不建 datasource**。守卫 `test/feature_boundaries_test.dart` R1–R5（R4/R5 棘轮，已清零）。
- `ResourceNotifier<T>` 只吃 `Future<T> Function()`，解析在 repository；`decodeList/decodeMap` 在 `shared/utils/json_decode.dart`。请求 DTO 归 domain。

## Dart / Flutter 陷阱
- ✅ `flutter test` 可跑，**先关代理**：`env no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同值 <sdk>/bin/flutter test`（否则 flutter_tester 的本地 WebSocket 走代理，报 `Invalid WebSocket upgrade request`）。
- **Flutter SDK = `/Users/annilq/Documents/fulttersdk/flutter`**（不在 PATH）。`flutter analyze` 很快但退出码常非 0 → 看输出 `No issues found!`。
- ⚠️ **`Row(crossAxisAlignment: stretch)` 必须包 `IntrinsicHeight`**：左色条行卡（左色条+`Expanded`）落在 `Column`/`ListView`/`CustomScrollView`（高度无界）里会抛 `BoxConstraints forces an infinite height`（`h=Infinity`）。`Column(stretch)` 是横向拉伸、**安全**。守卫 `test/stretch_row_guard_test.dart`（棘轮）。详见 ADR-0044。
- ⚠️ **`ShadButton` 不可放进会压缩它的容器**（`Expanded`/固定宽）：内部文字不收缩 → `RenderFlex overflowed`。并排按钮一律 `Wrap`。主题层按钮水平 padding 已各减 2 抵消 2px 描边增量。
- 相对 import `..` 越过 `lib/` 根时分析器「截断」不报错 → 层数自己数准。

## 视觉语言：新粗野（ADR-0044）
- 高饱和撞色 + 2px 墨黑描边 + 无模糊硬阴影 + 弹簧动效（弃 `Curves.easeOutBack`）。色块=**强调件**（≤卡片 40%、单屏大色块 ≤3 色相、列表行禁整行填充）；亮块配墨黑字、深块配白字（WCAG AA 实测）。
- 列表行用 `AppCard.listRow`（发丝边、无阴影），独立卡用 `AppCard`（2px+硬阴影）；学科三重编码 `AppTags.subject`+`SubjectMarkIcon`；新增 `AppBrutal`/`AppElevation`/`AppSprings`/`AppBrutalButton`；动效 `AppMotion`（PopIn/PressScale/ConfettiBurst，均尊重 reduce-motion）。
- **描边三档（`AppElevation`，禁写裸数字）**：2 `borderWidth` = 内容物体（卡/弹窗/浮层）；1.5 `borderWidthSm` = 密集列表小色块（chip/徽标/题号）；1 `borderWidthHairline` = 结构边与重复安静元素（顶栏底边/侧栏右缘/分隔线/`listRow`）。同屏结构边必须同档。
- **「白色物体在纸底没有边界」是头号陷阱**：`surfaceRaised` 纯白 vs 纸底 `#FDFBF7` 对比仅 ~1.02、`surfaceSunken` vs 白卡 ~1.09 —— 原先靠浅灰 `outline` 兜底，`outline` 换墨黑后**没写边的组件就失去边界**。修法是**补描边而非加粗**（墨黑边已有 ~19:1）。另：`Border.all(color:)` 默认 1px，必须显式写宽。
- **输入框描边刻意保持 1px**：与 `AppControl.inputStrut` 的 `heightOf - 4`（= 2×1px 边 + 2px 内部预留）及 tight 高度三向耦合，加粗会裁字。
- **隐式动画**（`AnimatedContainer`/`AnimatedPositioned`/骨架 shimmer）**不会自动尊重 reduce-motion**，须显式 `duration: reducedMotionOf(context) ? Duration.zero : ...`。
- 浮层阴影统一走 `_floatingShadows()`（暗色返回 `AppElevation.none`）；**别写 `shadows: const []`** 把 `_surfaceDecoration` 算好的阴影抹掉。
- 单一事实源 `.impeccable.md`；术语见 `CONTEXT.md` §设计语言。
- **铺开状态（2026-09-15 第三轮）**：页面层与 `shared/widgets` **均已铺完**。无需改：`home_screen`（组合根零裸样式）、`child_mastery_screen`、`mastery_board`、`app_toast`（本就是实心块）。待真机：① 选项块选中态 2px+硬阴影在 4 块同屏下是否过吵；② 发丝结构边与 2px 内容边同屏的粗细差观感。

## Git
- ✅ `git push origin main` 可通；⚠️ 常输出 `Everything up-to-date` 但其实**已成功**，以 `git ls-remote origin main` 比对 HEAD 为准。push 走环境代理（端口每会话变），失败先 `curl -x $HTTPS_PROXY https://github.com` 探活再重试。
- 提交按**逻辑批次**拆，正文写「为什么」；`chore(memory):` 可单独提交。`backend/.agents/` 未跟踪，**别顺手 commit**。

## 后端（引擎 / 密钥 / schema / 泄露）
- `decrypt()` 解不开只返 `None`（**密文永不出门**）；`ToolUnsupportedError`(无FC) vs `ProviderRequestError`(厂商拒绝) 落点 `agent_core/adapters/genkit.py#classify_failure`；禁用 `except Exception` 把引擎失败抹成「请添加模型」。
- `SECRET_KEY` 未配置时生成随机密钥落盘 `backend/.secret_key`，启动期冒烟（ADR-0041）。`env_file`/`DATABASE_URL` 均 CWD 无关。
- 工具 schema strict（ADR-0040）：可省略参数要有缺席编码（`""`/`0`/枚举含 `NO_FILTER="all"`），归一收口 `query/tools/_shared.py`。守卫 `tests/ai/test_query_tools_contract.py`。
- 助手推理/正文分流（ADR-0043，已修）：`TextDelta.kind`，`acc` 只收 TEXT；协议泄露判据分**强/弱两档**，强标记命中即判、**不得绑定工具名**。守卫 `tests/ai/test_tool_loop_bounds.py`。残留：默认模型 `deepseek-v4-flash` 多轮 tool loop 会退化成 XML 文本 → 对策是**减跳数**（`child_name` 一跳直达）。

## 后端测试 / 待办
- pytest 前 `cd backend && mv .env .env.hidden`（避 broker 读 .env），跑完恢复；用 `.venv/bin/ruff`、`.venv/bin/pytest`。偶发 `PermissionError: Sensitive content approval timed out` → 重跑即可。
- `Resource<T>` 迁移未完成（Models/DueReview/Review/Bank/Children 仍自建四态）；AI 集成层待业务闭环后整层重构；③/⑤ 重构无 ADR。`docs/adr/` 现 0001–0044。
- 已知未修小瑕疵：无。
