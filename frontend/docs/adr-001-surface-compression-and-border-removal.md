# ADR-001: Surface 色阶压缩 + Border 去除

**日期**: 2026-08-25
**状态**: 已接受
**决策者**: 用户 + AI 辅助

## 背景

当前 Flutter UI 存在以下问题：
1. **Border 过度使用**：34 处 `Border.all` 散布在卡片、容器、选项瓦片、顶部栏、面板上，视觉碎片化严重
2. **Surface 色阶过多**：5 级 surface（Lowest/Low/Container/High/Highest）+ 大量透明度变体（0.18/0.2/0.35/0.5/0.6/0.62/0.75/0.85/0.88），色彩不够简洁
3. **嵌套层次深**：卡片套容器套容器，不是真正的扁平化
4. **与设计指南矛盾**：`.impeccable.md` 规定「卡片用 1px 描边」，但用户希望更扁平

## 决策

### D1: Surface 色阶从 5 级压缩到 3 级

| 层级 | 用途 | 亮色值 | 暗色值 |
|------|------|--------|--------|
| `surface` | 页面背景 | `#FDF8F0` | `#1D1B17` |
| `surfaceRaised` | 卡片/容器（浮起） | `#FFFFF3` | `#2A261F` |
| `surfaceSunken` | 轨道/凹槽（下沉） | `#F4ECDA` | `#171512` |

- 旧字段名（surfaceContainerLowest 等）保留但映射到这 3 个值，保证向后兼容
- 新增 `surfaceRaised` / `surfaceSunken` 语义 getter，供新代码使用

### D2: 卡片/容器去除默认 border

- `ShadCardTheme.border` → `width: 0`
- `AppCard` 默认不画 border，仅靠 `surfaceRaised` 背景色与 `surface` 背景的色差建立层级
- 保留的 border 仅限：输入框 focus 态（`primary` 1.5px）、选项选中态（`primary` 2px）

### D3: 透明度变体清理

- 砍掉手动 `withValues(alpha: 0.18/0.2/0.35/0.5/0.6/0.62/0.75/0.85/0.88)` 调用
- Banner 背景直接用 `primaryContainer` / `secondaryContainer`，不叠透明度 border
- 需要弱化色时使用已有的 container 色令牌

### D4: 共享组件 border 清理

| 组件 | 变更 |
|------|------|
| `AppTopBar` | 移除底部 1px border，靠 surface 背景与内容区分 |
| `AppCard` | 移除默认 1px outline border |
| `AvatarSquircle` | 移除 1px outline border |
| `AppLoading._SkeletonCard` | 移除 1px outlineVariant border |
| `AppTextField` | 保留 input border（含 focus 态） |
| `AppPickerField` | 保留 input border |

### D5: 高频屏幕 border 清理

| 屏幕 | 变更 |
|------|------|
| `practice_screen.dart` | 问题容器/完成页/选项瓦片去 border（选项保留选中态 border） |
| `parent_dashboard.dart` | 统计卡/选择器/添加瓦片去 border + 修复 CupertinoIcons → LucideIcons |
| `child_home.dart` | Banner 去 border + 修复 CupertinoIcons → LucideIcons |
| `review_screen.dart` | 与 practice 对齐去 border |

## 设计原则更新

此 ADR 修订 `.impeccable.md` 中的「质感」约定：
- **旧**：卡片用 1px 描边 + 暖色填充（无重阴影）
- **新**：卡片无描边，仅靠 surfaceRaised 背景色与页面背景色差建立层级；保留输入框 focus 和选中态描边作为交互反馈信号

## 风险与缓解

- **层级感减弱**：去 border 后卡片可能不够突出 → 通过 surfaceRaised 与 surface 的色差 + 间距来补偿
- **进度条轨道对比度**：surfaceSunken 在暗色模式下较暗 → primary 绿色 fill 对比度反而更高
- **向后兼容**：旧字段名保留，只是值被压缩 → 业务代码无需大规模重命名
