# 娃娃学习 — 设计系统语境

本文件定义设计令牌与组件体系中特有的术语。不含通用编程概念。

## Language

**Accent（靛蓝强调色）**:
用于 selection、focus、progress 填充、链接文字的单一强调色（`#5E6AD2` 亮 / `#7B82EA` 暗）。CTA 按钮不使用 accent，而用近黑底白字保持重量感。
_Avoid_: primary（已废弃的暖绿角色名）、brandColor、themeColor

**Surface 层次**:
五级表面色阶：surface（内容区微暖白）/ surfaceRaised（卡片 `#FFFFFF`）/ surfaceHover（hover 态 `#F4F4F2`）/ surfaceSunken（侧栏/凹槽 `#F4F4F2`）/ surfaceActive（选中态药丸 `#EDEDF0`）。禁止手动 withValues(alpha:) 透明度变体。
_Avoid_: backgroundColor、cardColor

**Outline（描边）**:
卡片/分隔线的 1px 极细描边（`#ECECEA` 亮 / `#2A2A28` 暗）。hover 时描边加深至 outlineHover（`#D1D1CE`）。Linear 风格——用描边分层，不用阴影。
_Avoid_: border、divider、stroke

**密排字号阶梯（Dense Type Scale）**:
正文 15sp 基线的统一字号体系，双端共用。Inter 主西文/数字 + HarmonyOS Sans SC CJK 回退。每个字号有对应 tracking（标题负、正文零、小字正）。行高按用途区分（标题 1.2 / 紧凑文字 1.35 / 阅读文字 1.5）。
_Avoid_: 护眼大字、20sp 基线

**语义色（Semantic Colors）**:
降饱和的四档状态色底——positive（极淡绿 `#EFF5EC`）/ warning（极淡琥珀 `#FAF3E8`）/ error（极淡红 `#FCE8E6`）/ info（极淡靛蓝 `#EEF0FC`）。用于 badge/chip/icon 容器，不用于大面积背景。
_Avoid_: primaryContainer/secondaryContainer/tertiaryContainer（旧暖绿体系角色名）

**转场分级（Motion Tiers）**:
三档动画时长——交互态 120ms / 状态切换 200ms / 页面进入 300ms。交互态用 easeOut，页面进入用 easeInOut。loading→loaded 用 crossfade。
_Avoid_: 统一 200ms easeOut（旧做法）

**Hover 令牌（Hover State）**:
桌面壳下所有可交互元素（侧栏项、卡片、按钮）的 hover 反馈——surface 变 surfaceHover、outline 变 outlineHover。用 MouseRegion 或 Shad hover 回调实现。
_Avoid_: 无（旧做法完全没有 hover）
