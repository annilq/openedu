# Ticket 02 — 前端独立「运行轨迹」页（镜像双消费者）

- **What to build**: 新增独立入口/页面，只读运行轨迹口径（一次 AI 运行的全步骤：routing / tool_call / tool_result / generation / error 等 + 元数据 model/usage/latency_ms/safety），**不**进历史会话页、**不**进气泡。镜像后端「双消费者」：历史会话投影「气泡」、运行轨迹投影「全步骤 + 元数据」，同一张 `Conversation`/`Message` 表、两种口径。扩展既有导航密封类增加一个 case，所有入口只经单一 `_go(page)`；不另开并行导航状态。复用既有不套 Material 的控件树；新增页面/浮层真构建一次。文件规模按 `test/file_size_guard_test.dart` 基线登记（只许下调）。token/延迟展示依赖 ticket 01 落库有值。
- **Blocked by**: 01
- **Status**: ready-for-agent
- **验收清单**:
  - 轨迹页渲染一次运行的全步骤（routing / tool_call / tool_result 至少三类可见），且每步显示 model / token / latency（依赖 01）。
  - 轨迹页**不**把步骤渲染进历史会话气泡；历史会话页与轨迹页入口分离、互不混入。
  - 导航单源：扩展既有导航密封类增加 case，`teacher_nav_single_source_test` 无并行状态。
  - 全站禁 Material 控件：新增页面在不套 Material 的树里真构建，`flutter analyze` 认 `No issues found!`。
  - 文件规模棘轮：新增 widget 在 `test/file_size_guard_test.dart` 的 `_baseline` 登记（只许下调）。
  - `flutter test` 0 回归（先关代理）。

## 决策锚点

- **双消费者，不混入口**：轨迹页只读运行轨迹口径、历史页只读气泡口径，复用同一后端数据、两种前端投影——与班级管理「容器+下钻复用同一份后端」同一套方法论。
- **导航单源 + 禁 Material**：扩展既有密封类而非开并行状态；新增控件必须在不套 Material 的树里真构建。
- **token/延迟靠 01 喂数据**：本页只消费，不负责落库；01 没值时对应列显示占位而非崩溃。
