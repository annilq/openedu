# AI 助手形态收敛：家长端浮层退场，浮球改为打开整页

家长端的 AI 助手此前是「浮球 + 380×540 浮层面板」（`AssistantChatPanel`）。浮层尺寸与导航壳
没有任何关系：它既不齐侧栏、也不齐内容列，桌面 / 平板（device）下压在内容上，看起来像一张贴纸，
而不是这个界面的一个部分。娃娃端早已是整页（「问 AI 老师」页签），两端只是同一个助手的两个入口，
却有两套容器。本 ADR 把**浮层删掉**：浮球仍在，点开的是**整页**。

## 决策

- **家长端浮球改为 `Navigator.push` 整页 [AssistantChatPage]。**
  传 `showBack: true, isParent: true`；浮层形态及其 `AssistantChatPanel` / `_Header` / `_InputBar`
  一并删除。整页自带返回，浮球**不在整页上重复出现**——它固定在右下角，正好压住整页的输入栏
  （ADR-0036 的「每个角色恰好一个入口」不受影响：入口仍是这一个浮球）。

- **双端只有一个助手页面。** 娃娃端页签与家长端浮球打开的是同一个 `AssistantChatPage`：
  同一 `assistantNotifierProvider`、同一 `AssistantMessageList`，只用 `isParent` 切换**标题**
  （「问 AI 老师」/「AI 学习助手」）与**空态引导**口径。
  - 文案必须分角色：家长能出题 / 查任务 / 查学情，娃娃端只暴露伴学答疑——这是后端
    `AgentRuntime.visible_businesses(role)` 说了算的，前端不能把「只讲学习内容，其他问题不回答哦」
    照搬给家长，也不能对娃娃承诺「可以出题」。

- **整页自带宽度兜底。** 经 `Navigator.push` 打开的页面**不在导航壳的 `contentWide` 兜底范围内**
  （ADR-0045）。故本页自己套上限：消息列表与输入栏同宽同轴（`AppLayout.contentWide`），
  避免「气泡收在中间一列、输入框横贯全屏」。
  - 同时把消息区的 `Center` 改为 `Align(topCenter)`：`Center` 连竖向一起居中，消息少时整列气泡
    浮在屏幕中间，与本仓「内容贴顶自然布局」的口径冲突。

- **浮球进焦点树。** 原先它是裸 `GestureDetector`（桌面端 Tab 跳不过来、Enter 点不动，而
  `flutter analyze` 照不出来，ADR-0045/0046）。改走 `AppFocusableAction`，按压反馈与 `AppCard`
  同一套语义：整块下沉 + 硬阴影收拢。

- **令牌**：新增 `AppLayout.tapTargetLg = 52`（浮球边长，此前是裸 `52`）；**删除
  `AppLayout.contentFloat = 380`**——浮层是它唯一的消费方，留一个没有消费方的档位只会让人猜
  「什么该用它」。

## Considered Options

1. **保留浮层，只调尺寸 / 贴边**：问题性质不变（浮层仍与壳无关，窄屏挤、宽屏飘），拒绝。
2. **家长端也用「壳内页面」**（保留侧栏，靠 `body` 替换 + 页面顶栏返回）：桌面端侧栏常驻更连贯，
   但紧凑档家长端会出现「壳的汉堡顶栏 + 页面自己的返回顶栏」两条 52px 顶栏；且侧栏没有对应导航项，
   高亮会停在上一页，读起来像「点击没生效」。拒绝。
3. **浮球 push 整页**（采用）：与本仓既有的整页（`PracticeScreen` 等）同一条路径，紧凑 / 中 / 大屏行为
   一致，没有双顶栏与高亮歧义。

## 守卫

`frontend/test/assistant_launcher_test.dart`：

- 点击浮球打开的 `AssistantChatPage` **铺满可用宽度**（1200 宽视口下）——浮层时代这里只有 380；
- 键盘：Tab 落到浮球、Enter 同样打开整页（裸 `GestureDetector` 时代为 0）；
- 家长形态标题为「AI 学习助手」，不再是娃娃端的「问 AI 老师」。

## 后果

- 桌面 / 平板下助手成为与其它整页同构的页面，随可用宽度自然适配；浮层与「浮层专用宽度档」一并消失。
- 已知代价：整页会盖住侧栏，家长看着任务列表问 AI 需要先返回（与练习页同款取舍）。
- 后续若要「边看列表边问 AI」（侧栏常驻的右侧助手栏），那是一个**新的 master-detail 编排**，
  应在 `AdaptiveShell` 的 `detail` 槽位上另开决策，而不是把浮层加回来。
