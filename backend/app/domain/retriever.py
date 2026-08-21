"""教材知识库检索层（T11，故事 24/25 / AC-305 检索能力）。

ticket 边界：**仅实现检索能力，不解决教材授权**（🔴 ADR-012 版权硬门槛，
对外分发前须另行解决）。当前为内置**自编**知识点库（不涉及任何教材版权内容），
后期可按需平滑切换联网检索或向量库——接入方式与 `build_provider` 相同的工厂模式，
不破坏业务层（TutorService 只依赖 `KnowledgeRetriever` 抽象）。
"""

import warnings
from abc import ABC, abstractmethod
from dataclasses import dataclass

from app.core.config import settings


@dataclass(frozen=True)
class KnowledgeChunk:
    """检索命中的一段知识点内容（结构化、对齐教材的口径）。"""

    subject: str
    grade: int
    knowledge_point: str
    content: str
    source: str  # builtin | web | vector


class KnowledgeRetriever(ABC):
    """按学科/年级/知识点检索知识库，返回排序后的命中文档。"""

    @abstractmethod
    def retrieve(
        self,
        *,
        subject: str,
        grade: int,
        knowledge_point: str,
        query: str,
    ) -> list[KnowledgeChunk]: ...


# ── 内置自编知识点库（Mock 实现的数据源，纯自编内容、无版权风险）──
_BUILTIN_KNOWLEDGE: list[dict] = [
    {
        "subject": "数学",
        "grade": 2,
        "knowledge_point": "加法",
        "content": "加法是求两个数合起来是多少。计算时个位先相加，满十向前一位进一，再把十位加起来。",
    },
    {
        "subject": "数学",
        "grade": 2,
        "knowledge_point": "减法",
        "content": "减法是求一个数去掉一部分还剩多少。个位不够减时，向十位借一当十再减。",
    },
    {
        "subject": "数学",
        "grade": 4,
        "knowledge_point": "乘法",
        "content": "乘法是求几个相同加数相加的简便运算，例如 4×3 表示 3 个 4 相加。",
    },
    {
        "subject": "数学",
        "grade": 4,
        "knowledge_point": "分数",
        "content": "分数表示整体的一部分，如 3/4 表示把一个整体平均分成 4 份、取其中 3 份。",
    },
    {
        "subject": "语文",
        "grade": 2,
        "knowledge_point": "拼音",
        "content": "拼音由声母、韵母和声调组成。读准声调是正确拼读的关键，轻声也要留意。",
    },
    {
        "subject": "语文",
        "grade": 4,
        "knowledge_point": "修辞",
        "content": "常见修辞有比喻、拟人、排比、夸张。比喻是把一种事物比作另一种更形象的事物。",
    },
    {
        "subject": "英语",
        "grade": 2,
        "knowledge_point": "字母",
        "content": "英语有 26 个字母，分元音字母（a/e/i/o/u）和辅音字母，注意大小写对应。",
    },
    {
        "subject": "英语",
        "grade": 4,
        "knowledge_point": "时态",
        "content": "一般现在时表示经常发生的动作，一般过去时表示已经发生的动作，注意动词的规则变化。",
    },
]


class MockKnowledgeRetriever(KnowledgeRetriever):
    """内置自编知识点检索：学科精确匹配 + 知识点/查询关键词命中。

    匹配规则：knowledge_point 与 query 拼成检索文本，库内知识点是检索文本的子串
    （或反过来），即视为命中——低年级知识点命名简单，宽松匹配足够。
    """

    def retrieve(
        self,
        *,
        subject: str,
        grade: int,
        knowledge_point: str,
        query: str,
    ) -> list[KnowledgeChunk]:
        parts = [knowledge_point, query or ""]
        text = " ".join(p for p in parts if p).lower()
        if not text:  # 无检索词时不做全量返回
            return []
        results = []
        for item in _BUILTIN_KNOWLEDGE:
            # 学科 + 年级双精确：适龄优先（低年级不会拿到高年级内容）
            if item["subject"] != subject or item["grade"] != grade:
                continue
            kp = item["knowledge_point"].lower()
            if kp in text or text in kp:
                results.append(KnowledgeChunk(**item, source="builtin"))
        return results


def build_retriever() -> KnowledgeRetriever:
    """按配置选择检索实现；未知值回退 mock 并告警，保证服务始终可启动。"""
    provider = settings.RETRIEVER_PROVIDER
    if provider in ("mock", "builtin"):
        return MockKnowledgeRetriever()
    if provider != "vector":  # vector 为预留值：后续接入 embedding 向量库
        warnings.warn(
            f"未知 RETRIEVER_PROVIDER={provider!r}，回退到内置 mock 检索",
            stacklevel=2,
        )
    return MockKnowledgeRetriever()


__all__ = [
    "KnowledgeChunk",
    "KnowledgeRetriever",
    "MockKnowledgeRetriever",
    "build_retriever",
]
