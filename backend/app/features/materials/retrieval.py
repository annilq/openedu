"""VectorKnowledgeRetriever（ADR-0055 §7/§13）：dense + 词法双路 + RRF 融合。

填进 ``build_retriever()`` 的 ``vector`` 分支，出题调用方零改动。

实现取舍：
- **dense**：查询经 embedding 服务向量化，与 chunk 的 float32 BLOB 算余弦；
- **sparse → 词法现算**：BGE-M3 的 sparse 输出要本地权重（不进镜像），改为对
  候选片段做查询时 BM25-lite（字符二元组 + ASCII 词）——单教师数千片段，
  现算比维护稀疏索引便宜，效果同族（抓「37+48」这类 dense 区分度差的精确词）；
- **RRF 融合**：只看排名不看分数尺度（``1/(k+rank)``，k=60）；
- **过滤**：teacher + subject + grade（自动过滤，教师不勾选）+ 版本戳——
  ``embed_model`` / ``chunker_ver`` 与当前配置不符的行**直接跳过**（stale
  语义在检索侧的落点，双保险：状态机管展示，版本戳管真值）；
- embedding 不可用 / 失败**不阻塞出题**：降级为纯词法检索并告警。
"""

from __future__ import annotations

import math
import re
import uuid
import warnings
from collections import Counter

from sqlmodel import Session, select

from app.core.config import settings
from app.db.models import CHUNKER_VERSION, Material, MaterialChunk
from app.domain.retriever import KnowledgeChunk
from app.features.materials.embedder import (
    EmbeddingUnavailableError,
    embed_texts,
)
from app.features.materials.indexing import decode_vector

_TOP_K = 5
_RRF_K = 60
_SNIPPET_CHARS = 80

_ASCII_WORD = re.compile(r"[a-zA-Z0-9]+")


def _tokenize(text: str) -> list[str]:
    """中文按字符二元组、ASCII 按词——BM25-lite 的词元。"""
    t = text.lower()
    tokens = _ASCII_WORD.findall(t)
    han = re.sub(r"[^一-龥]", "", t)
    tokens.extend(han[i : i + 2] for i in range(len(han) - 1))
    return tokens


def _lexical_scores(
    query_tokens: list[str], docs_tokens: list[list[str]]
) -> list[float]:
    """BM25-lite：候选集内算 IDF，k1/b 取常用值。返回与 docs 等长的分数。"""
    k1, b = 1.5, 0.75
    n = len(docs_tokens)
    if n == 0:
        return []
    avgdl = sum(len(d) for d in docs_tokens) / n or 1
    df = Counter()
    for d in docs_tokens:
        df.update(set(d))
    scores = []
    for d in docs_tokens:
        tf = Counter(d)
        score = 0.0
        for term in set(query_tokens):
            if term not in tf:
                continue
            idf = math.log(1 + (n - df[term] + 0.5) / (df[term] + 0.5))
            score += (
                idf
                * tf[term]
                * (k1 + 1)
                / (tf[term] + k1 * (1 - b + b * len(d) / avgdl))
            )
        scores.append(score)
    return scores


def _cosine(a: list[float], b: list[float]) -> float:
    num = sum(x * y for x, y in zip(a, b, strict=True))
    da = math.sqrt(sum(x * x for x in a)) or 1e-9
    db = math.sqrt(sum(y * y for y in b)) or 1e-9
    return num / (da * db)


def _rrf_fuse(rankings: list[list[int]], top_k: int) -> list[int]:
    """多个排名列表 → RRF 融合分。输入是各路的候选下标序列（最优在前）。"""
    fused: Counter[int] = Counter()
    for ranking in rankings:
        for rank, idx in enumerate(ranking):
            fused[idx] += 1 / (_RRF_K + rank + 1)
    return [idx for idx, _ in fused.most_common(top_k)]


class VectorKnowledgeRetriever:
    """教师私有资料库检索：结构化四元组查询 → 排序后的 KnowledgeChunk。"""

    def __init__(self, session: Session, teacher_id: uuid.UUID):
        self._session = session
        self._teacher_id = teacher_id

    def retrieve(
        self,
        *,
        subject: str,
        grade: int,
        knowledge_point: str,
        query: str,
    ) -> list[KnowledgeChunk]:
        # 候选集硬边界：教师归属 + 版本戳（stale 向量天然出局）。
        # 学科 / 年级是「已知时」的便利过滤（ADR-0055 §13 原为出题管线设计，那时
        # subject+grade 一定随请求带来）。但答疑问答（tutor）往往拿不到：
        #   教师端 grade 恒为 0、自由文本又几乎无法可靠识别学科（「轴对称图形」不含
        #   「数学」二字）。若在此强过滤，候选集直接被打空 → RAG 静默失效，
        #   模型只能凭自身知识编造。故 subject 为空 / grade<=0 时退化为跨全库语义检索，
        #   隔离仍由 teacher_id 保证（ADR-0055 §2：检索范围永远按教师归属隔离）。
        conditions = [
            MaterialChunk.teacher_id == self._teacher_id,
            MaterialChunk.embed_model == settings.EMBEDDING_MODEL,
            MaterialChunk.chunker_ver == CHUNKER_VERSION,
        ]
        if subject:
            conditions.append(MaterialChunk.subject == subject)
        if grade and grade > 0:
            conditions.append(MaterialChunk.grade == grade)
        rows = self._session.exec(
            select(MaterialChunk, Material.name)  # type: ignore[call-overload]
            .join(Material, Material.id == MaterialChunk.material_id)
            .where(*conditions)
            .limit(2000)
        ).all()
        if not rows:
            return []
        chunks: list[MaterialChunk] = [r[0] for r in rows]
        names: list[str] = [r[1] for r in rows]

        qtext = (
            " ".join(x for x in (query, knowledge_point) if x).strip()
            or knowledge_point
        )
        rankings: list[list[int]] = []

        # 路 1：dense 余弦（失败降级，不阻塞出题）
        try:
            qvec = self._embed_query_sync(qtext)
        except EmbeddingUnavailableError as e:
            warnings.warn(f"dense 检索降级为纯词法：{e}", stacklevel=2)
            qvec = None
        if qvec is not None:
            sims = [
                (_cosine(qvec, decode_vector(c.embedding)), i)
                for i, c in enumerate(chunks)
                if c.embedding
            ]
            sims.sort(key=lambda x: -x[0])
            rankings.append([i for _, i in sims])

        # 路 2：词法 BM25-lite
        docs_tokens = [_tokenize(c.content) for c in chunks]
        lex = _lexical_scores(_tokenize(qtext), docs_tokens)
        rankings.append(sorted(range(len(chunks)), key=lambda i: -lex[i]))

        fused = _rrf_fuse(rankings, _TOP_K)
        return [
            KnowledgeChunk(
                subject=subject,
                grade=grade,
                knowledge_point=knowledge_point,
                content=chunks[i].content,
                source="vector",
                source_name=names[i],
                material_id=str(chunks[i].material_id)
                if chunks[i].material_id is not None
                else None,
                chunk_id=str(chunks[i].id),
            )
            for i in fused
        ]

    def _embed_query_sync(self, text: str) -> list[float]:
        from app.core.async_bridge import run_async

        return run_async(embed_texts([text]))[0]


__all__ = ["VectorKnowledgeRetriever"]
