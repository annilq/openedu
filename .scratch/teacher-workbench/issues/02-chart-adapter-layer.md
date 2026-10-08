# 02: 图表适配器层 analytics_charts.dart

**What to build:** 落地项目图表适配器层，作为 fl_chart 与业务页之间的强制护栏。适配器 `AppBarChart` / `AppDonutChart` / `AppGroupedBarChart` / `AppStackedBarChart` 在内部统一注入新粗野视觉令牌——`borderRadius: 0` 直角、`borderColor: outline` / `borderWidth: 2`（卡片级描边令牌，密集小标记用 1.5）、配色走 `AppColors`（纸底/墨黑/强调色块，禁用 fl_chart 默认蓝紫渐变）、图表元素本身不画模糊阴影（硬阴影由卡片承载）。交互层由 fl_chart 内置 `BarTouchData`/`PieTouchData` 提供：点按高亮、悬浮 tooltip、active 区段反白；薄弱知识点「点击钻取分析层」直接挂 `onTouchCallback`。业务页**严禁裸用**裸 fl_chart。附快照/ golden 测试覆盖四图 + 暗色模式令牌读取。

**Blocked by:** 01 (基座——fl_chart 依赖 + Material 冒烟 gate)

**Status:** ready-for-agent

- [ ] 四个适配器渲染：环形（掌握度仪表，中心 `X/Y`）、横向条形（薄弱知识点）、分组横向条（正确率）、竖向堆叠条（错题分布 活跃/毕业）。
- [ ] 视觉对齐：直角、2px 描边、outline 配色、无模糊阴影；暗色模式令牌读取正确。
- [ ] 交互：tooltip 显示分项数值；薄弱知识点 tap 回调可挂载钻取；区段高亮生效。
- [ ] 护栏：全仓 grep 确认无业务代码直接 import `fl_chart` 的 `BarChart`/`PieChart`（只经适配器）。
- [ ] 快照/ golden 测试通过；`flutter analyze` 无 issue。
