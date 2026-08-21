"""知识库检索层单测（T11，故事 24/25 / AC-305 检索能力）。

覆盖：mock 检索命中/未命中/子串匹配、工厂选择与未知值回退。
"""

import pytest

from app.core.config import settings
from app.domain.retriever import (
    MockKnowledgeRetriever,
    build_retriever,
)


def test_retrieve_hit_returns_structured_chunk():
    r = MockKnowledgeRetriever()
    chunks = r.retrieve(
        subject="数学", grade=2, knowledge_point="加法", query="23+45 怎么算"
    )
    assert len(chunks) == 1
    c = chunks[0]
    assert c.subject == "数学"
    assert c.grade == 2
    assert c.knowledge_point == "加法"
    assert "进一" in c.content
    assert c.source == "builtin"


def test_retrieve_returns_multiple_subject_matches():
    r = MockKnowledgeRetriever()
    chunks = r.retrieve(subject="英语", grade=2, knowledge_point="", query="字母")
    assert len(chunks) == 1
    assert chunks[0].knowledge_point == "字母"


def test_retrieve_no_hit_returns_empty():
    r = MockKnowledgeRetriever()
    chunks = r.retrieve(
        subject="数学", grade=2, knowledge_point="几何", query="三角形"
    )
    assert chunks == []


def test_retrieve_filters_by_subject():
    """同知识点跨学科不串库：数学查「加法」不应命中英语库。"""
    r = MockKnowledgeRetriever()
    chunks = r.retrieve(subject="英语", grade=2, knowledge_point="加法", query="")
    assert chunks == []


def test_retrieve_filters_by_grade():
    """同学科跨年级不串：4 年级问「加法」不命中二年级条目（适龄优先）。"""
    r = MockKnowledgeRetriever()
    chunks = r.retrieve(subject="数学", grade=4, knowledge_point="加法", query="")
    assert chunks == []


def test_retrieve_empty_query_and_kp_returns_empty():
    """无检索词时不做全量返回。"""
    r = MockKnowledgeRetriever()
    chunks = r.retrieve(subject="数学", grade=2, knowledge_point="", query="")
    assert chunks == []


def test_retrieve_partial_knowledge_point_hit():
    """知识点子串匹配：kp=「加」应命中「加法」。"""
    r = MockKnowledgeRetriever()
    chunks = r.retrieve(subject="数学", grade=2, knowledge_point="加", query="")
    assert len(chunks) == 1
    assert chunks[0].knowledge_point == "加法"


def test_build_retriever_default_is_mock():
    assert isinstance(build_retriever(), MockKnowledgeRetriever)


def test_build_retriever_unknown_falls_back_to_mock(monkeypatch):
    monkeypatch.setattr(settings, "RETRIEVER_PROVIDER", "typo_xyz")
    with pytest.warns(UserWarning, match="回退"):
        retriever = build_retriever()
    assert isinstance(retriever, MockKnowledgeRetriever)
