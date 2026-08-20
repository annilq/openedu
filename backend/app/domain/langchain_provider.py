import json

from app.core.config import settings
from app.domain.provider import GeneratedQuestion, LLMProvider

_SYSTEM = (
    "你是面向小学到初中学生的出题与批改助手。"
    "只输出适合对应年级、纯学习相关的内容，禁止任何不当、危险或超出教材的内容。"
    "始终以 JSON 返回，不要附带多余说明。"
)


class LangChainProvider(LLMProvider):
    """真实大模型实现（国产模型走 OpenAI 兼容端点）。延迟导入，mock 模式无需安装 langchain。

    LLM_PROVIDER 配置来源：
      - langchain：读 LLM_BASE_URL / LLM_MODEL / LLM_API_KEY
      - deepseek ：读 DEEPSEEK_BASE_URL / DEEPSEEK_MODEL / DEEPSEEK_API_KEY（快捷预设）
    """

    def __init__(self) -> None:
        if self._config_key() is None:
            raise RuntimeError(
                "LLM_PROVIDER=langchain 需要配置 LLM_BASE_URL 与 LLM_MODEL；"
                "或 LLM_PROVIDER=deepseek 并配置 DEEPSEEK_API_KEY"
            )

    def _config_key(self) -> str | None:
        """返回当前 provider 对应的配置键名；缺少必要配置时返回 None。"""
        if settings.LLM_PROVIDER == "deepseek":
            return "DEEPSEEK" if settings.DEEPSEEK_API_KEY else None
        if settings.LLM_PROVIDER == "langchain" and settings.LLM_BASE_URL and settings.LLM_MODEL:
            return "LLM"
        return None

    def _build_model(self):
        from langchain_openai import ChatOpenAI

        prefix = self._config_key()
        if prefix is None:  # 防御：配置被改空时给出明确错误
            raise RuntimeError("LLM 配置缺失，无法构建模型")
        if prefix == "DEEPSEEK":
            return ChatOpenAI(
                model=settings.DEEPSEEK_MODEL,
                temperature=settings.LLM_TEMPERATURE,
                api_key=settings.DEEPSEEK_API_KEY,
                base_url=settings.DEEPSEEK_BASE_URL,
            )
        return ChatOpenAI(
            model=settings.LLM_MODEL,
            temperature=settings.LLM_TEMPERATURE,
            api_key=settings.LLM_API_KEY or "none",
            base_url=settings.LLM_BASE_URL,
        )

    async def generate_question(
        self, *, subject, grade, knowledge_point, qtype, difficulty
    ) -> GeneratedQuestion:
        model = self._build_model()
        prompt = (
            f"请为{grade}年级《{subject}》的“{knowledge_point}”出一道{qtype}题，"
            f"难度{difficulty}。返回 JSON："
            '{"stem": str, "options": list[str]|null, "answer": str, "explanation": str}'
        )
        resp = await model.ainvoke(
            [{"role": "system", "content": _SYSTEM}, {"role": "user", "content": prompt}]
        )
        data = self._parse_json(resp.content)
        return GeneratedQuestion(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            qtype=qtype,
            stem=data.get("stem", ""),
            options=data.get("options"),
            answer=data.get("answer", ""),
            explanation=data.get("explanation", ""),
            difficulty=difficulty,
        )

    async def grade_open(self, *, question, student_answer) -> dict:
        model = self._build_model()
        prompt = (
            f"题目：{question.stem}\n学生作答：{student_answer}\n"
            '请批改并返回 JSON：{"correct": bool, "score": float, "explanation": str}'
        )
        resp = await model.ainvoke(
            [{"role": "system", "content": _SYSTEM}, {"role": "user", "content": prompt}]
        )
        data = self._parse_json(resp.content)
        return {
            "correct": bool(data.get("correct", False)),
            "score": float(data.get("score", 0.0)),
            "explanation": data.get("explanation", ""),
        }

    async def tutor(
        self, *, grade, subject, knowledge_point, context, question
    ) -> str:
        from app.domain.safety import tutor_system_prompt

        model = self._build_model()
        ctx = f"\n相关上下文：{context}" if context else ""
        prompt = (
            f"学生问：{question}\n"
            f"所属知识点：{knowledge_point}{ctx}\n"
            "请用简洁、鼓励的语气，结合知识点给出适合该年级学生的分步讲解，"
            "必要时举例。只讲解学习相关内容，不要回答与学习无关的话题。"
        )
        resp = await model.ainvoke(
            [
                {"role": "system", "content": tutor_system_prompt(grade, subject)},
                {"role": "user", "content": prompt},
            ]
        )
        return self._as_text(resp.content)

    @staticmethod
    def _as_text(content) -> str:
        if isinstance(content, str):
            return content
        # langchain 返回的是 list[dict] 或 AIMessage，统一取文本
        if isinstance(content, list):
            return "".join(
                part.get("text", "") if isinstance(part, dict) else str(part)
                for part in content
            )
        return str(getattr(content, "content", content))

    @staticmethod
    def _parse_json(content) -> dict:
        text = content if isinstance(content, str) else getattr(content, "content", str(content))
        try:
            start, end = text.find("{"), text.rfind("}")
            return json.loads(text[start : end + 1]) if start != -1 and end != -1 else {}
        except (json.JSONDecodeError, ValueError):
            # 解析失败兜底，绝不崩溃
            return {}
