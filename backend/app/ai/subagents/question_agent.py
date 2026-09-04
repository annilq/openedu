"""出题 SubAgent（ADR-0021）：接 RAG（KnowledgeRetriever）+ 学科 Persona 注入。

把此前零调用的 ``KnowledgeRetriever`` 接进出题流，解决「纯自由生成、未对齐教材」痛点。
复用 ``LLMProvider.generate_question``（已追加可选 ``rag_context`` / ``persona_hint`` 参数），
对既有出题路径零破坏——不传这两个参数时行为与原来完全一致。

两条路径均经本 SubAgent 派发：
- 非流式（家长批量出题 / 落库）：``handle`` → provider（或路由带 session 解析出的 engine）；
- 流式（预览逐题浮现）：``stream`` → 先算好每题 RAG/Persona，再委托 genkit flow 产出。

genkit 相关导入一律**惰性**（写在方法内），保证本包可在不加载 genkit 重型依赖的前提下被单测。
"""
from __future__ import annotations

from app.ai.subagents.base import BaseSubAgent, SubAgentContext
from app.ai.subagents.subject_personas import get_subject_persona


def expand_specs(specs) -> list[dict]:
    """把 specs（dict 或对象）按 count 展开为「每题一条」列表（顺序即 q_index）。

    流式与非流式共用：保证 q_index 分配、focus_interest 轮询在两条路径上完全一致。
    """
    items: list[dict] = []
    for sp in specs:
        if isinstance(sp, dict):
            subject = str(sp.get("subject", ""))
            grade = int(sp.get("grade", 0))
            knowledge_point = str(sp.get("knowledge_point", ""))
            qtype = str(sp.get("qtype", ""))
            difficulty = str(sp.get("difficulty", "medium"))
            count = int(sp.get("count", 1))
        else:
            subject = str(sp.subject)
            grade = int(sp.grade)
            knowledge_point = str(sp.knowledge_point)
            qtype = str(sp.qtype)
            difficulty = str(sp.difficulty)
            count = int(sp.count)
        for _ in range(max(0, count)):
            items.append(
                {
                    "subject": subject,
                    "grade": grade,
                    "knowledge_point": knowledge_point,
                    "qtype": qtype,
                    "difficulty": difficulty,
                }
            )
    return items


def build_question_context(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    query: str | None,
    retriever=None,
) -> tuple[str | None, str]:
    """计算 ``(rag_context, persona_hint)``：RAG 命中 + 学科 Persona 渲染。

    纯计算（不触 genkit），可单测；非流式与流式路径共用，保证增强口径一致。
    """
    rag_context: str | None = None
    if retriever is not None and (knowledge_point or query):
        chunks = retriever.retrieve(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            query=query or knowledge_point,
        )
        if chunks:
            rag_context = "\n".join(f"- {c.content}" for c in chunks)
    persona_hint = get_subject_persona(subject).render()
    return rag_context, persona_hint


class QuestionSubAgent(BaseSubAgent):
    business = "question"

    def build_augments(
        self,
        specs,
        *,
        interests: list[str] | None = None,
        focus_interests: list[str] | None = None,
    ) -> tuple[dict[int, str], dict[int, str]]:
        """为每个 q_index 预计算 RAG 上下文与学科 Persona（流式路径用）。

        返回 ``(rag_contexts, persona_hints)``，键为 q_index（与 expand_specs 顺序一致）。
        注：检索在首帧前一次性完成；本地/自编库开销可忽略，接入远程检索源时改为惰性更佳。
        """
        rag_contexts: dict[int, str] = {}
        persona_hints: dict[int, str] = {}
        n_focus = len(focus_interests) if focus_interests else 0
        for idx, item in enumerate(expand_specs(specs)):
            focus = focus_interests[idx % n_focus] if n_focus else None
            rag, persona = build_question_context(
                subject=item["subject"],
                grade=item["grade"],
                knowledge_point=item["knowledge_point"],
                query=focus or item["knowledge_point"],
                retriever=self.retriever,
            )
            if rag:
                rag_contexts[idx] = rag
            persona_hints[idx] = persona
        return rag_contexts, persona_hints

    async def handle(self, intent: dict, ctx: SubAgentContext):
        subject = ctx.subject or intent.get("subject", "")
        grade = ctx.grade or intent.get("grade", 0)
        kp = ctx.knowledge_point or intent.get("knowledge_point", "")
        qtype = intent.get("qtype", "choice")
        difficulty = intent.get("difficulty", "medium")

        # 1) RAG + 学科 Persona（与流式路径共用同一计算口径）。
        rag_context, persona_hint = build_question_context(
            subject=subject,
            grade=grade,
            knowledge_point=kp,
            query=ctx.question or kp,
            retriever=self.retriever,
        )

        # 2) 引擎优先：路由带 session 解析出的 ModelConfig 自定义模型；否则走 provider 抽象。
        if self.engine is not None:
            # 惰性导入：避免本包在仅做单测时加载 genkit 重型依赖。
            from app.ai import generate_question as genkit_generate_question

            return await genkit_generate_question(
                self.engine,
                subject=subject,
                grade=grade,
                knowledge_point=kp,
                qtype=qtype,
                difficulty=difficulty,
                interests=intent.get("interests"),
                focus_interest=intent.get("focus_interest"),
                rag_context=rag_context,
                persona_hint=persona_hint,
            )

        # 3) 复用既有出题能力；rag_context / persona_hint 作为可选增强。
        return await self.provider.generate_question(
            subject=subject,
            grade=grade,
            knowledge_point=kp,
            qtype=qtype,
            difficulty=difficulty,
            interests=intent.get("interests"),
            focus_interest=intent.get("focus_interest"),
            rag_context=rag_context,
            persona_hint=persona_hint,
        )

    async def stream(
        self,
        *,
        specs,
        interests: list[str] | None = None,
        focus_interests: list[str] | None = None,
        engine=None,
    ):
        """流式出题：先算好每题 RAG/Persona，再委托 genkit flow 逐题产出信封 chunk。"""
        engine = engine if engine is not None else self.engine
        rag_contexts, persona_hints = self.build_augments(
            specs, interests=interests, focus_interests=focus_interests
        )
        # 惰性导入：同上，保持 subagents 包不依赖 genkit。
        from app.ai import generate_questions_stream

        async for chunk in generate_questions_stream(
            engine,
            specs=specs,
            interests=interests,
            focus_interests=focus_interests,
            rag_contexts=rag_contexts,
            persona_hints=persona_hints,
        ):
            yield chunk
