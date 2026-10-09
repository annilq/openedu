# Slide Outline

## Meta
- Topic: 教育智能体设计与应用 —— openedu 中小学错题复习智能体（任务契合度分析与提交方案）
- Scenario: 教师参加校级「教育智能体设计与应用」任务/比赛，需用本项目作为申报案例，配套演示 PPT（用于演示视频录屏）
- Content Source: provided（openedu 项目文档：AGENTS.md / docs/agents/ai.md / architecture.md / model_catalog.py）
- Research: skip — 内容全部来自项目既有文档，无需联网检索
- Style: 简洁专业教育科技风 — 深蓝主色 + 翠绿(成长) + 琥珀强调；浅色为主、封面/结尾深色；大字号、强对比、SVG 数据图
- Slide Count: 11
- Generated At: 2026-10-09

## Source Materials
- AGENTS.md：项目定位、技术栈、硬约束速览
- docs/agents/ai.md：AI 助手卡片协议、提示词/路由/推理分流、守卫测试
- docs/agents/architecture.md：agent_core 自研内核、SSE 单一入口、SubAgent 结构、RAG/Provider 抽象
- backend/app/ai/model_catalog.py：内置服务商目录含 DeepSeek/通义千问/智谱/豆包/Kimi 等国产模型

## Slide-by-Slide Outline
1. **Slide 1 — Cover (L02 BoldCover, dark)** — openedu：可提交的教育智能体案例 | Meta: 开发与应用报告配套演示 · 提交人 教师 annilq
2. **Slide 2 — 任务解读 (L19 List)** — 四类应用场景 + 三件交付物 + 国产技术底座
3. **Slide 3 — 项目概况 (L05 Concept+Visual)** — openedu = 中小学错题复习应用 + AI 学习助手贯穿全流程
4. **Slide 4 — 场景契合度 (L15 Matrix 2x2)** — 教学赋能/知识库/多模型/自研框架 四项全中
5. **Slide 5 — 功能架构 (L16 IconRow 5卡)** — AI助手·智能出题批改·知识库RAG·互动讲解·学习闭环
6. **Slide 6 — 平台/技术选择 (L13 Process)** — 自研 agent_core + 国产模型适配 + Flutter/FastAPI
7. **Slide 7 — 开发过程①提示词工程 (L05)** — 意图路由(guide/query)·学科Persona·推理分流 + 代码片段
8. **Slide 8 — 开发过程②知识库RAG (L05 mirror)** — 教材上传→知识点→RAG(BGE-M3) + 代码片段
9. **Slide 9 — 应用过程与效果 (L17 Data+Insight)** — 间隔重复阶段间隔 1/2/4/7/15 天 SVG 曲线 + 洞察
10. **Slide 10 — 创新与反思 (L08 Compare2)** — 左：创新点 / 右：待改进
11. **Slide 11 — 结论与落地清单 (L20 Closing, dark)** — 可作提交 + 三件交付物清单

## Visual Rhythm Notes
- 深色强调页：Slide 1（封面）、Slide 11（结尾）
- 含数据/图：Slide 9（间隔重复 SVG 曲线）
- 每页 ≥2 装饰元素（几何块/分隔线/图标），背景用浅渐变（封面/结尾深渐变）
