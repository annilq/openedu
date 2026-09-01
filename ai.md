AI-Native Software Project Specification

1. 背景

传统项目通常通过 Template / Starter 初始化项目：

Template
   ↓
项目代码
   ↓
开发

这种方式的核心是复用已有代码，但存在以下问题：

* Template 是静态的，容易过时
* 不同项目往往需要大量修改 Template
* 技术栈升级后，Template 维护成本较高
* AI Agent 已经具备根据规范和文档动态生成代码的能力

因此，项目初始化方式可以逐渐从：

代码模板驱动

转向：

架构、规范、知识和 AI Agent 驱动

Template 不会消失，而是退化为项目 Bootstrap / Skeleton。

⸻

2. 核心理念

AI-Native 项目的核心不是保存大量预先写好的代码，而是保存：

Architecture
+
Rules
+
Skills
+
External Knowledge
+
Project Documentation

由 Code Agent 根据这些信息动态完成：

Requirement
    ↓
Planning
    ↓
Design
    ↓
Implementation
    ↓
Test
    ↓
Review
    ↓
Documentation

⸻

3. 核心组成

3.1 AGENTS.md

AGENTS.md 是项目的 AI 开发协议入口。

它不应该保存所有知识，而应该告诉 Agent：

* 项目是什么
* 项目架构在哪里
* 项目规则在哪里
* 文档在哪里
* Skill 如何使用
* 标准开发流程是什么
* 技术知识从哪里获取

例如：

AGENTS.md
    ↓
Architecture
Rules
Skills
Documentation
Development Process
External Knowledge

因此：

AGENTS.md 是 Index / Contract，而不是 Knowledge Base。

⸻

3.2 Architecture

Architecture 描述：

系统应该如何设计。

例如：

Frontend
  React / Next.js
Backend
  FastAPI
Database
  PostgreSQL
Architecture
  Clean Architecture
Authentication
  JWT

Architecture 解决的是：

Why / What Architecture

⸻

3.3 Rules

Rules 描述：

项目开发过程中什么可以做，什么不能做。

例如：

Controller 不允许直接访问 Repository
Service 不允许直接操作数据库
所有 API 必须定义 Request / Response Schema
数据库变更必须通过 Migration
所有 Feature 必须包含测试

Rules 解决的是：

Constraints

⸻

3.4 Skills

Skill 描述：

如何执行某一类开发任务。

Skill 可以分为三类。

Process Skill

定义开发流程。

例如：

/grill-with-docs

用于需求澄清、问题发现和文档生成。

Technology Skill

定义如何使用某个技术。

例如：

Next.js
FastAPI
PostgreSQL
React

Project Skill

定义当前项目中特定领域的实现方式。

例如：

project-api
project-database
project-auth
project-testing

因此：

Process Skill
    = 怎么做开发
Technology Skill
    = 怎么正确使用技术
Project Skill
    = 本项目应该怎么实现

⸻

4. External Knowledge

技术本身的知识不应该大量复制到项目中。

项目只保存外部知识源：

sources:
  - name: nextjs
    type: llm-txt
    url: https://...
  - name: fastapi
    type: llm-txt
    url: https://...
  - name: postgres
    type: llm-txt
    url: https://...

llm.txt / 官方文档属于：

External Technical Knowledge

它解决：

这个技术本身是什么，以及应该如何使用。

因此：

Architecture
    = 为什么选择以及如何组织
Skill
    = 在项目中如何使用
llm.txt / Official Docs
    = 技术本身的最新知识

项目通过 URL 引用知识源，而不是复制完整文档，以保持知识源的更新。

对于生产项目，可以进一步增加版本或 Snapshot 机制，以保证 Agent 行为可复现。

⸻

5. Agent 与项目规范的关系

不同 Code Agent：

Claude Code
Codex
Pi
Cursor
Gemini CLI
...

拥有不同的：

* Skill 系统
* 全局目录
* 配置方式
* 默认规则
* Extension / Plugin 机制

因此不应该要求所有 Agent 使用完全相同的内部机制。

项目只需要定义统一的：

Project Contract

即：

AGENTS.md
+
docs
+
architecture
+
rules
+
project skills

Agent 可以通过自己的机制加载这些内容。

因此：

Agent 是运行时实现，AGENTS.md 是项目级协议。

⸻

6. Global Skill 与 Project Skill

Skill 可以存在于两个层级。

Global Skill

安装在 Agent 全局环境：

~/.agents/skills/

用于复用通用能力，例如：

grill-with-docs
React
Next.js
PostgreSQL

Project Skill

存在于项目中：

project/
└── .agents/
    └── skills/

用于描述项目特有规范。

例如：

project-api
project-auth
project-database

最终：

Global Skills
      +
Project Skills
      +
AGENTS.md
      +
External Knowledge
      ↓
    Agent

⸻

7. 推荐项目结构

一个 AI-Native 项目可以采用：

project/
│
├── AGENTS.md
│
├── docs/
│   ├── product/
│   ├── requirements/
│   ├── ux/
│   ├── architecture/
│   ├── database/
│   └── decisions/
│
├── .agents/
│   └── skills/
│       ├── project-api/
│       ├── project-database/
│       └── project-testing/
│
├── src/
│
└── tests/

其中：

AGENTS.md
    ↓
项目 AI 协议入口
docs/
    ↓
项目知识与设计
.agents/skills/
    ↓
项目专属开发能力
src/
    ↓
实际代码
tests/
    ↓
测试

⸻

8. 推荐初始化流程

新项目不再只是：

选择 Starter
    ↓
Clone
    ↓
修改代码

而是：

Create Project
      ↓
Bootstrap / Template
      ↓
setup-matt-pocock-skills
      ↓
初始化标准 Skill / Docs
      ↓
创建 AGENTS.md
      ↓
定义 Architecture
      ↓
定义 Rules
      ↓
配置 Technology Skills
      ↓
配置 External Knowledge
      ↓
开始 AI Development

其中 Template 只负责：

Bootstrap

而不是定义整个项目的开发方式。

⸻

9. 标准开发流程

推荐形成统一的 AI Development Lifecycle：

Idea
  ↓
Requirement Discovery
  ↓
Product / UX Design
  ↓
Architecture
  ↓
Technical Design
  ↓
Implementation
  ↓
Testing
  ↓
Review
  ↓
Documentation

例如：

Idea
 ↓
/grill-with-docs
 ↓
Requirement Document
 ↓
Architecture
 ↓
Technology Skills
 ↓
External Documentation
 ↓
Code Agent
 ↓
Code
 ↓
Test
 ↓
Review

核心原则：

Skill 定义流程，Agent 执行流程。

⸻

10. 整体架构

最终可以抽象成：

                    AI-Native Project
                           │
                     ┌─────▼─────┐
                     │ AGENTS.md │
                     │  Project  │
                     │  Contract │
                     └─────┬─────┘
                           │
          ┌────────────────┼────────────────┐
          ↓                ↓                ↓
    Architecture         Rules           Process
          │                │              Skills
          │                │                │
          └────────────────┼────────────────┘
                           ↓
                     Project Skills
                           │
                ┌──────────┴──────────┐
                ↓                     ↓
          Technology Skills     External Knowledge
                                      │
                                llm.txt / Docs
                └──────────┬──────────┘
                           ↓
                       Code Agent
                           ↓
                    Plan / Code / Test
                           ↓
                       Project

⸻

11. 核心职责划分

组件	核心职责
Template	Bootstrap / Skeleton
AGENTS.md	AI 项目协议入口
Architecture	定义系统如何设计
Rules	定义工程约束
Process Skill	定义开发流程
Technology Skill	定义技术使用方式
Project Skill	定义项目特定实现方式
llm.txt / Docs	提供最新技术知识
Code Agent	执行开发任务
docs	保存项目知识、需求和设计

⸻

12. 最终目标

目标不是创建一个新的“大型 AI Agent”。

而是建立一个：

Agent-Agnostic 的 AI Software Engineering Layer

让：

Claude
Codex
Pi
Cursor
Gemini
未来其他 Agent

都能够进入同一个项目，并理解：

这个项目是什么
↓
为什么这样设计
↓
应该遵循什么规则
↓
应该执行什么开发流程
↓
应该使用哪些 Skill
↓
技术知识在哪里
↓
最终应该生成什么代码

因此，项目本身逐渐从：

Code + Template

演变为：

Project
=
Code
+
Architecture
+
Rules
+
Skills
+
Documentation
+
External Knowledge

这构成了 AI-Native Software Development 的基础项目模型。

如果后续要真正落地，我建议下一步不是继续增加概念，而是把这份说明进一步压缩成一份 AGENTS.md 的实际标准模板，直接定义“一个新 AI 项目应该有哪些目录、哪些字段、Agent 按什么顺序工作”。