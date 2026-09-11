# 边界规则与设计系统约束

跨层调用与视觉令牌遵守统一边界，约束写在设计系统源头（原 ADR-0003）。

- **设计约束 D**：surface 微暖白、卡片纯白 + 1px 极细描边、无阴影（`frontend/.../app_theme.dart:116`）；间距全部取自 `AppSpacing` 令牌、无魔法数字，随紧凑度 / 双模式自动缩放（`:1561`）。
- **令牌单一事实源**：排版、学科色、转场时长（三档 + Child 庆祝档）均由统一令牌推导，组件不得硬编码。
- **层边界**：AI 工具按 `shared_tool` / `query` / `tasks` 分层注册；退役的 `shared_tool` 包随 tasks 一并下线，将来复用须按助手统一端点语义重建（`tests/ai/test_layering_invariants.py:43`，原 ADR-0033 关联）。

**Consequences**：主题层与令牌脱节会在 `theme_preview` 自检中以 ✗ 暴露；任何新增色彩 / 间距必须走令牌，禁止散落字面量。
