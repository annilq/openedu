# 提取共享做题组件，而非仅本地拆分

practice_screen 与 review_screen 在「选项卡片、答题结果弹窗、完成页正确率卡、带 loading 的提交按钮」上存在大面积逐行重复。决定：在把各屏按区块拆到 `features/<f>/presentation/widgets/` 的同时，把上述四处真实重复抽到 `shared/widgets/`（`App*` 语义组件），由 practice 与 review 共用；tutor 的 `SubjectToggle`/消息气泡/欢迎提示仅本特性使用，留在各自 feature 内不抽取。不建统一 quiz 流程组件（那会合并 practice/review 的状态机，属行为变更，超出"拆文件"范畴）。

## Considered Options

- **A. 纯本地拆分**：每屏各自 `widgets/`，不抽共享。零行为风险，但 OptionTile/结果弹窗/完成页在两个 feature 各存一份副本，留下重复债务。已否决。
- **B. 本地拆分 + 抽共享（采纳）**：消除 practice/review 真实重复，符合 `.impeccable.md` 语义组件与令牌纪律。
- **C. 建共享 quiz 模块**：把整个「逐题答题→判题→完成」流程统一成可复用流程组件，合并 practice/review 状态机。范围过大、属行为变更，已否决。

## Consequences

- 共享组件命名归入 `App*` 前缀（与 AppTags/AppBadge 等一致）。确认清单：新增 3 个 `AppOptionTile` / `AppAnswerResultDialog` / `AppQuizResultCard`，并给现有 `AppPrimaryButton` 增加可选 `icon` 参数（吸收 review/tutor_chat/tutor_quota 三处手搓 loading 按钮，复用其已内置的 `loading`+loaderCircle 逻辑）。不新增 `AppLoadingButton`，避免与 `AppPrimaryButton` 职责重叠。
- `AppQuizResultCard` 内部固定计算 `ResultTone` 分档、icon、正确率、进度条（两屏逐行一致）；以参数/插槽承载差异：`title` / `subtitle` / `trailing`(底部按钮) / `overlay`(可选，承载 practice 全对彩带)。
- `AppAnswerResultDialog({bool correct, String title, Widget content, bool animateIcon=false})` 包裹 `AppDialog.alert`，内部按 `correct` 渲染 36x36 图标容器（tertiary/error + check/refreshCw，两屏一致）；标题文案、内容 Widget、是否 PopIn 由调用方传。
- `AppOptionTile({int index, String text, bool selected, VoidCallback? onTap, bool disabled=false})` 内部统一用 `PressScale`（项目手势标准），`disabled` 承载 review 提交中禁用态；合并 practice `_OptionTile` 与 review `_ReviewOptionTile`。
- practice 与 review 完成页存在差异（practice 有全对彩带 + 打卡按钮；review 有"返回首页" + "自动升级"文案），共享完成卡以插槽承载差异，不硬合并文案。
- 抽取后两屏行为必须保持一致，回归测试需覆盖提交、判题、完成三态。
- 新共享组件放入 `shared/widgets/` 各自独立文件（与 app_dialog.dart/app_error.dart 一致），**不**塞进已 950+ 行的 `app_theme.dart`（该文件后续应单独拆分，本次不处理）。
- 实施中发现：3 处 loading 按钮宽度行为不同（tutor_quota 保存满宽、review 提交内容宽、tutor_chat 发送行内），原 `AppPrimaryButton` 的 `fullWidth:false` 分支套 `Center` 会破坏行内/列内布局。已确认无调用方使用 `fullWidth:false`（Center 为死代码），故移除 `Center` 包装，使 `fullWidth` 仅控制 `ShadButton.expands`——三处按钮均可复用 `AppPrimaryButton`（满宽用 `fullWidth:true`，内容/行内用 `fullWidth:false`），消除 `loaderCircle.rotate` 手搓副本。
