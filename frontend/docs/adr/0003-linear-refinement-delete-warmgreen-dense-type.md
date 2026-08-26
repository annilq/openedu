# ADR-0003: Linear 化重设计——密排字号 + 靛蓝强调 + 删暖绿

- **Status**: Accepted
- **Date**: 2026-08-25
- **Supersedes**: ADR-0002 中"暖绿主题保留为可切换备选"的条款

## Context

ADR-0002 将默认主题改为中性灰白并引入桌面分栏壳，但保留了暖绿主题作为备选，且未触及排版密度和交互精细度。实际使用中，应用主要面向家长（专业管理工具），儿童使用比例小。当前正文 20sp、暖色护眼基调、零 hover 态、无键盘快捷键的设计与"专业工作台"定位不符，参考 Linear/Notion 的字号、配色、交互工艺均有明显差距。

## Decision

1. **删掉暖绿主题**：移除 `AppColorScheme.warmGreen` 分支及 `light`/`dark` 暖绿令牌对，只保留一套中性+靛蓝令牌。`AppColorScheme` enum 简化或删除。
2. **密排统一字号**：正文基线从 20sp 降至 15sp，双端共用一套阶梯。引入 Inter 作为西文/数字主字体，HarmonyOS Sans SC 作 CJK 回退，Inter .ttf 打包进 assets。
3. **靛蓝强调色**：新增 `#5E6AD2`（暗色 `#7B82EA`）用于 selection/focus/progress/link；CTA 按钮仍用近黑底白字。
4. **Linear 式表面层次**：surface 微暖白 `#FBFAFA`、卡片 `#FFFFFF` + 1px `#ECECEA` 描边、hover `#F4F4F2`、**无阴影**。暗色对应 `#0F0F0E` / `#161615` / `#2A2A28`。
5. **交互 Tier 1+2**：全局 hover 态、press 反馈、转场分级（120ms 交互 / 200ms 状态 / 300ms 页面）、crossfade、tooltip、Cmd+K 命令面板、侧栏首字母快捷键。**不要半透明 focus ring**，focus 用 bg 变化表达。
6. **语义色降饱和**：保留 positive/warning/error/info 四档语义色，但底色降至 Linear 级极淡色块（如 `#EFF5EC` 绿 / `#FAF3E8` 琥珀 / `#FCE8E6` 红），不再用原 `#43A047`/`#F97316`/`#38BDF8`。
7. **重写设计约定**：`.impeccable.md` 优先级翻转——家长专业体验 > 低龄友好，删除 ≥20sp / 暖白护眼 / 暖绿为默认等条款。

## Consequences

- **正面**：设计语言统一（一套令牌），维护成本减半；排版/交互工艺对标 Linear/Notion；家长端信息密度提升。
- **负面**：删除暖绿令牌不可逆（重建需恢复 4 套色对）；娃娃端正文字号从 20sp 降到 15sp，对低频儿童用户可接受但放弃了原"低龄友好"承诺；所有语义组件（AppCard/AppTags/AppBadge/SectionTitle 等）需在令牌层重建配色。
- **影响范围**：`app_theme.dart` 令牌全量重写；`app.dart` 主题装配简化；`desktop_shell.dart`/`app_sidebar.dart` 配色更新；全部业务屏幕的字号引用更新。

## Alternatives considered

- **保留暖绿 + 中性双主题**：否决。双主题维护成本高，且暖绿与 Linear 交互体系审美冲突，混用违和。
- **仅家长端 Linear 化、娃娃端保持大字暖色**：否决。用户明确"双端"，且维护双密度/双审美的复杂度不值。
- **保留 focus ring**：否决。用户要求"简洁"，半透明环视觉噪音大。
