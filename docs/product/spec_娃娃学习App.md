# Spec: 娃娃学习 App（小学→初中，平板优先）

> 形态：Flutter 原生平板 App + Python/LangChain 后端 + PostgreSQL
> 配套权威文档（细化见彼）：`../decisions/娃娃学习App_ADR.md`、`../architecture/技术架构_后端.md`、`../architecture/技术架构_Flutter.md`、`功能规格_PRD_全三期.md`、`../decisions/娃娃学习App_术语表.md`
> 本 spec 为**面向 agent 实现**的合并视图，遵循 to-spec 模板。

---

## Problem Statement

作为家长，我希望为两个娃娃（二年级、四年级，规划至初中）提供一个日常学习工具，覆盖数学、语文、英语等学科。现有市面产品普遍存在三个问题：不贴合我家教材进度、家长缺乏可见的管控与进度、过度游戏化导致本末倒置。我需要一个「家长当班主任、AI 辅助出题与讲解、娃娃在平板上完成练习与打卡」的家庭私用闭环。

---

## Solution

一套平板原生 App（Flutter），后端为 Python/FastChain（LangChain）服务 + PostgreSQL，分期交付：

- **一期**：家长按「学科+年级+知识点+题型+难度+题量」AI 出题并建任务；娃娃在平板上点选作答、即时批改与解析；完成任务打卡；家长查看正确率与连续打卡天数。
- **二期**：答错题自动归集，按遗忘曲线推送复习，生成知识点掌握度看板。
- **三期**：娃娃可就题目/知识点自由提问，AI 给出适龄讲解；教材知识库（前期联网检索、后期 RAG）支撑；双层内容安全 + 家长可见日志。

架构上**可换模型、可换框架、可上云**，且 MockProvider 模式下无外部依赖即可跑通完整闭环。

---

## User Stories

1. As a parent, I want to register and log in, so that I can manage my children's learning.
2. As a parent, I want to create child accounts with a grade, so that each child has isolated progress and tasks.
3. As a parent, I want to generate a practice task by selecting subject, grade, knowledge point, question type, difficulty, and count, so that I can target weak areas.
4. As a parent, I want the generated task to include correct answers on the parent side, so that I can verify question quality.
5. As a child, I want to see only my assigned tasks for today, so that I know what to do.
6. As a child, I want to answer questions by tapping/selecting on a tablet, so that it is easy and low-friction.
7. As a child, I want immediate feedback (correct/incorrect + explanation) after each answer, so that I learn instantly.
8. As a child, I want to never see the answer keys, so that I cannot cheat.
9. As a child or parent, I want to check in a completed task, so that progress is recorded.
10. As a parent, I want to view each child's accuracy, streak days, and total check-in days, so that I know who needs attention.
11. As the system, I want to fall back to a MockProvider when no LLM key is configured, so that the full loop runs with zero external dependencies.
12. As the system, I want the LLM provider to be pluggable via configuration, so that swapping models requires no business-code change.
13. As the system, I want wrong answers auto-collected into a wrong-questions set, so that review is possible.
14. As a child, I want to be reminded to review mistakes on a forgetting-curve schedule (e.g. 1/2/4/7/15 days), so that I retain better.
15. As a child, I want reviewing to reuse the same answering and grading flow as normal practice, so that the experience is consistent.
16. As a parent, I want a per-knowledge-point mastery dashboard, so that I can see learning progress.
17. As the system, I want a repeated wrong answer to reset the forgetting-curve timer, so that mastery is genuine.
18. As a child, I want to ask the AI about a question or concept in natural language, so that I get an age-appropriate explanation.
19. As the system, I want intent routing before answering, so that the query dispatches to the right capability (explain vs. generate vs. tutor).
20. As the system, I want a content-safety layer applied to all AI output, so that only age-appropriate, learning-related content is shown.
21. As the system, I want unsafe or jailbreak responses intercepted and surfaced to the parent, so that the child never sees violations.
22. As a parent, I want to view all AI interaction logs, so that I can monitor what my child asked.
23. As the system, I want to enforce a daily AI time limit set by the parent, so that usage is bounded.
24. As the system, I want to prefer knowledge-base (RAG) retrieval when available, so that answers align with the textbook.
25. As a parent, I want to manage the textbook knowledge base, so that content matches our curriculum.
26. As a parent, I want to set a daily usage time limit and content scope, so that I control exposure.
27. As the system, I want passwords hashed with bcrypt and auth via JWT, so that accounts are secure.
28. As the system, I want the frontend structured in Clean Architecture with Riverpod, so that it is testable and extensible.

---

## Implementation Decisions

- **Frontend**: Flutter native (iOS/Android, tablet-first). Clean Architecture with three layers (presentation / domain / data), dependency points inward to domain. State management via **Riverpod** (`StateNotifierProvider` + freezed states); DI via Riverpod provider composition + service-locator pattern. Codegen with `freezed` + `auto_route` + `build_runner`. Networking via **Dio** with interceptors (JWT injection, unified error → `HttpException`). Local storage via `shared_preferences` (token, parent settings, offline wrong-questions cache). Feature modules: `authentication`, `home`, `practice`, `checkin`, `children`, `profile`; reserved `wrong_questions` (phase 2), `ai_tutor` (phase 3). Tablet adaptation: ≥20sp text, warm eye-care theme, large tap targets, landscape-friendly.

- **Backend**: FastAPI + **SQLModel** (sync) + PostgreSQL (SQLite fallback for local dev). Based on [`fastapi/full-stack-fastapi-template`](https://github.com/fastapi/full-stack-fastapi-template) (ADR-013): model-is-schema convention, `app/core/` + `app/api/` + `app/crud.py` + `app/domain/` layering, UUID primary keys, `pyproject.toml` (hatchling). Auth via **pyjwt** + **pwdlib** (Argon2+bcrypt, replaces passlib). Config via `pydantic-settings` (env / `.env`). Python >=3.14.

- **Domain layer (core abstraction)**: business depends only on an `LLMProvider` interface; vendor adaptation lives solely inside the provider implementations. Do **not** re-wrap LangChain's own provider abstraction (ADR-003). A factory selects the implementation by config and imports LangChain lazily (keeps mock mode dependency-free). The prototype encoded this precisely:

  ```python
  @dataclass
  class GeneratedQuestion:
      subject, grade, knowledge_point, qtype   # qtype: choice|fill|calc|open
      stem, options, answer, explanation, difficulty

  class LLMProvider(ABC):
      async def generate_question(self, *, subject, grade, knowledge_point, qtype, difficulty) -> GeneratedQuestion: ...
      async def grade_open(self, *, question, student_answer) -> dict: ...
  ```

  `QuestionGenerator` and `Grader` are thin wrappers over `LLMProvider`. `Grader` scores objective types (`choice|fill|calc`) by normalized string equality; delegates `open` to the provider.

- **Question types**: `choice` (options), `fill`, `calc`, `open`. Objective answers stored as `answer`; **never** returned to the child endpoints.

- **Answer isolation**: `Question.answer` is returned only on the parent `POST /tasks/generate` response (`include_answer=True`); the child `GET /tasks/today` always returns `None` for answer.

- **Authorization**: `require_parent` guards parent endpoints; child endpoints verify `role=child` and data ownership; violations return 403/400.

- **Data model**: `User` (self-referencing `parent_id` distinguishing parent/child), `Task`, `Question`, `AnswerRecord`, `Checkin`. Accuracy = correct/total per child; streak = consecutive days with a check-in ending today.

- **API contracts** (base `/`, Bearer JWT):
  - `POST /auth/register`, `POST /auth/login` → token + user
  - `POST /children`, `GET /children` (parent)
  - `POST /tasks/generate` (parent; returns answers), `GET /tasks/today` (child; no answers)
  - `POST /tasks/{id}/answer` (child) → correct/score/explanation
  - `POST /tasks/{id}/checkin`, `GET /tasks/children/{id}/progress` (parent)
  - `GET /health`
  - Reserved for later: `/review/*`, `/tutor/*`, `/knowledge/*`

- **Reserved extension interfaces** (architecture pre-wired, not yet built): `domain/retriever.py` (`KnowledgeRetriever`), `domain/intent.py` (`IntentRouter`), `domain/review.py` + scheduler (`ReviewScheduler`), `domain/tutor.py` (`Tutor`), `domain/safety.py` (`SafetyGuard`). All follow the same abstract + factory pattern.

- **Deployment**: `docker-compose` runs `postgres` + `backend`; backend config via env (DB URL, JWT secret, CORS, LLM provider/base/model/key). Stateless backend + externalized DB makes it cloud-portable.

---

## Testing Decisions

- **Good test = external behavior only**, never implementation details. Prefer the highest seam that still exercises real logic.
- **Primary seam — HTTP API contract (integration)**: drive the app through FastAPI `TestClient` end-to-end: register → add child → generate task → today → answer → checkin → progress. This is the highest-value single seam and is fully decoupled from the Flutter implementation. Assert on response shapes and authorization outcomes, not internal calls. Uses the template's `conftest.py` convention (TestClient + SQLite override).
- **Secondary seam — domain unit tests**: `Grader` normalization/scoring and the `LLMProvider` contract (a fake provider returning a `GeneratedQuestion`; verify grading delegates correctly). Pure, fast, no network.
- **Modules to test**: `domain` (Grader, QuestionGenerator contract, provider factory selection), API routes (`auth`, `children`, `tasks`), and the progress/streak computation.
- **Prior art**: the loop test (`tests/api/routes/test_loop.py`) already validated the full happy path in mock mode and caught three real bugs (bcrypt/passlib conflict → switched to pwdlib, missing greenlet, `func.count().where` misuse). pytest suite (2 passed) covers the happy path + error paths: duplicate username (400), child hitting parent endpoint (403), answer hidden on `/today`, unauthenticated (401).
- **Frontend**: widget/provider tests with `mocktail`, mirroring `lib` structure per the Flutter architecture doc; test notifier state transitions (Idle/Loading/Success/Error) with a mocked repository.

---

## Out of Scope

- Subjective items (essays, oral, long-reading comprehension) — deferred beyond the initial phase-3 scope.
- Public distribution / commercialization — textbook copyright must be resolved first (hard gate, ADR-012).
- Real-time multi-device sync beyond a cloud-ready architecture.
- Strong gamification (leaderboards, role progression) — deferred to junior-high stage.
- Authoring actual textbook content or obtaining copyright licenses (a legal/business step, not engineering).

---

## Further Notes

- 🔴 **Textbook copyright is a hard launch gate (ADR-012)**: private/family use is fine; any distribution requires authorization or public-domain/self-authored content.
- MockProvider ensures the closed loop runs with zero external dependencies (validated locally end-to-end with pytest, backend error-free).
- LangChain is imported lazily so mock mode needs no `langchain` install.
- Backend is based on fastapi/full-stack-fastapi-template (ADR-013): SQLModel (sync), pyjwt + pwdlib, UUID keys, template layering. React frontend / email / Traefik / alembic were stripped.
- Triage label for publishing: `ready-for-agent`.
