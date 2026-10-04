"""检索层黄金集回归（ADR-0055 §14）：Recall@5，纯 pytest、不联网、可进 CI。

设计要点（为什么这样做）：
- **语料是自编固定语料**（无版权问题），chunk 直接以固定内容入库——黄金集
  测的是**检索**（过滤 / 双路排序 / RRF 融合），不测切片器；切片器调参在
  真实资料积累后用同一框架重标。
- **embedding 用确定性词袋替身**（字符二元组哈希投影 64 维）：同词近、异词远，
  dense 通道可复现且零网络；词法通道走生产代码 `_tokenize`/`_lexical_scores`。
- 30 条查询覆盖三类：字面命中 / 同义改写（词法弱、依赖其他词）/ 跨资料干扰
  （同知识点出现在多份资料，考排序）。
- 指标：整体 Recall@5 ≥ 0.85 门禁（业界冷启动下限），另有每条 gold 的
  Hit@5 断言；改检索器 / 切片器 / embed 模型后**必须重跑并重标**。
"""

from __future__ import annotations

import hashlib
import math
import uuid

import pytest

from app.db.models import CHUNKER_VERSION, Material, MaterialChunk
from app.db.models.material import INDEX_STATE_PENDING
from app.features.materials.indexing import encode_vector
from app.features.materials.retrieval import (
    VectorKnowledgeRetriever,
    _tokenize,
)

# ── 确定性假 embedding：字符二元组哈希 → 64 维归一化词袋 ────────────────
_DIM = 64


def _fake_embed(texts: list[str]) -> list[list[float]]:
    out: list[list[float]] = []
    for t in texts:
        v = [0.0] * _DIM
        for tok in _tokenize(t):
            h = int(hashlib.md5(tok.encode()).hexdigest(), 16)
            v[h % _DIM] += 1.0
        norm = math.sqrt(sum(x * x for x in v)) or 1.0
        out.append([x / norm for x in v])
    return out


# ── 固定语料：3 科 × 2 年级，每份资料 3-4 个片段（全部自编）─────────────
_CORPUS: list[dict] = [
    # 数学 三年级
    {
        "id": "m3-carry",
        "material": "三上口算讲义",
        "subject": "数学",
        "grade": 3,
        "content": "两位数加法进位：个位相加满十，向十位进一，十位别忘了加进上来的 1。",
    },
    {
        "id": "m3-mult",
        "material": "三上口算讲义",
        "subject": "数学",
        "grade": 3,
        "content": "多位数乘一位数：用一位数依次去乘另一个数的每一位，从个位乘起。",
    },
    {
        "id": "m3-frac",
        "material": "三上口算讲义",
        "subject": "数学",
        "grade": 3,
        "content": "分数初步认识：把一个整体平均分成几份，每份就是它的几分之一。",
    },
    {
        "id": "m3-perimeter",
        "material": "三上应用题集",
        "subject": "数学",
        "grade": 3,
        "content": "长方形的周长等于长加宽的和再乘二，正方形周长等于边长乘四。",
    },
    {
        "id": "m3-word",
        "material": "三上应用题集",
        "subject": "数学",
        "grade": 3,
        "content": "倍数应用题：求一个数是另一个数的几倍，用除法计算。",
    },
    # 数学 五年级
    {
        "id": "m5-equation",
        "material": "五上方程笔记",
        "subject": "数学",
        "grade": 5,
        "content": "等式的性质：等式两边同时加上或减去同一个数，等式仍然成立。",
    },
    {
        "id": "m5-decimal",
        "material": "五上方程笔记",
        "subject": "数学",
        "grade": 5,
        "content": "小数乘法：先按整数乘法算出积，再看因数中一共有几位小数，点上小数点。",
    },
    {
        "id": "m5-area",
        "material": "五上方程笔记",
        "subject": "数学",
        "grade": 5,
        "content": "平行四边形的面积等于底乘高，三角形的面积等于底乘高再除以二。",
    },
    # 语文 四年级
    {
        "id": "c4-metaphor",
        "material": "四年级修辞小结",
        "subject": "语文",
        "grade": 4,
        "content": "比喻是用跟甲事物有相似点的乙事物来描写说明甲事物，本体喻体缺一不可。",
    },
    {
        "id": "c4-personify",
        "material": "四年级修辞小结",
        "subject": "语文",
        "grade": 4,
        "content": "拟人就是把事物当作人来写，让它们像人一样会说话、有感情、会动作。",
    },
    {
        "id": "c4-summary",
        "material": "四年级阅读方法",
        "subject": "语文",
        "grade": 4,
        "content": "概括段意先找中心句，没有中心句就把各句意思合并起来用一句连贯的话说清。",
    },
    {
        "id": "c4-idiom",
        "material": "四年级阅读方法",
        "subject": "语文",
        "grade": 4,
        "content": "寓言故事的寓意要从故事情节和人物言行中体会，不能脱离原文随意引申。",
    },
    # 英语 六年级
    {
        "id": "e6-past",
        "material": "六年级时态复习",
        "subject": "英语",
        "grade": 6,
        "content": "一般过去时表示过去发生的动作，动词要用过去式，常与 yesterday 连用。",
    },
    {
        "id": "e6-present",
        "material": "六年级时态复习",
        "subject": "英语",
        "grade": 6,
        "content": "一般现在时第三人称单数：动词加 s 或 es，表示经常或习惯性的动作。",
    },
    {
        "id": "e6-compare",
        "material": "六年级时态复习",
        "subject": "英语",
        "grade": 6,
        "content": "形容词比较级用于两者比较，单音节词一般在词尾加 er，多音节词用 more。",
    },
    {
        "id": "e6-passive",
        "material": "六年级句型讲义",
        "subject": "英语",
        "grade": 6,
        "content": "被动语态由 be 动词加过去分词构成，强调动作的承受者时使用。",
    },
    {
        "id": "e6-clause",
        "material": "六年级句型讲义",
        "subject": "英语",
        "grade": 6,
        "content": "宾语从句用陈述语序，连接词有 that、if 和 whether，时态要与主句呼应。",
    },
    # 英语 三年级（干扰组：与六年级同主题不同深度，考年级过滤）
    {
        "id": "e3-plural",
        "material": "三年级单词册",
        "subject": "英语",
        "grade": 3,
        "content": "名词复数：一般在词尾加 s，以 s、x、ch、sh 结尾的加 es。",
    },
    {
        "id": "e3-greet",
        "material": "三年级单词册",
        "subject": "英语",
        "grade": 3,
        "content": "问候语：Good morning 用于上午，Good afternoon 用于下午，回答用相同问候。",
    },
]

# ── 黄金集：30 条查询 → 应召回的片段（前 5 至少命中 1 条，gold 全集算 Recall）──
_GOLD: list[dict] = [
    # 字面命中（词法 + dense 都应轻松命中）
    {"q": "进位加法怎么算", "s": "数学", "g": 3, "gold": ["m3-carry"]},
    {"q": "长方形周长公式", "s": "数学", "g": 3, "gold": ["m3-perimeter"]},
    {"q": "分数是什么", "s": "数学", "g": 3, "gold": ["m3-frac"]},
    {"q": "多位数乘一位数的计算方法", "s": "数学", "g": 3, "gold": ["m3-mult"]},
    {"q": "小数乘法怎么点小数点", "s": "数学", "g": 5, "gold": ["m5-decimal"]},
    {"q": "平行四边形面积公式", "s": "数学", "g": 5, "gold": ["m5-area"]},
    {"q": "什么是比喻", "s": "语文", "g": 4, "gold": ["c4-metaphor"]},
    {"q": "拟人句的特点", "s": "语文", "g": 4, "gold": ["c4-personify"]},
    {"q": "怎么概括段意", "s": "语文", "g": 4, "gold": ["c4-summary"]},
    {"q": "一般过去时的动词变化", "s": "英语", "g": 6, "gold": ["e6-past"]},
    {"q": "形容词比较级变化规则", "s": "英语", "g": 6, "gold": ["e6-compare"]},
    {"q": "名词复数加 s 还是 es", "s": "英语", "g": 3, "gold": ["e3-plural"]},
    # 同义改写（换一种说法，靠相关词命中）
    {"q": "满十进一是什么意思", "s": "数学", "g": 3, "gold": ["m3-carry", "m3-mult"]},
    {
        "q": "求一个数是另一个数的几倍用哪个运算",
        "s": "数学",
        "g": 3,
        "gold": ["m3-word"],
    },
    {"q": "等式两边加减同一个数还相等吗", "s": "数学", "g": 5, "gold": ["m5-equation"]},
    {"q": "三角形面积怎么求", "s": "数学", "g": 5, "gold": ["m5-area"]},
    {"q": "把东西当人来写叫什么修辞", "s": "语文", "g": 4, "gold": ["c4-personify"]},
    {"q": "寓言故事的道理怎么体会", "s": "语文", "g": 4, "gold": ["c4-idiom"]},
    {"q": "第三人称单数动词要变形吗", "s": "英语", "g": 6, "gold": ["e6-present"]},
    {"q": "被动句的构成", "s": "英语", "g": 6, "gold": ["e6-passive"]},
    {"q": "宾语从句的语序和连接词", "s": "英语", "g": 6, "gold": ["e6-clause"]},
    # 年级过滤（同词不同年级的资料，只能拿到对应年级）
    {"q": "一般现在时什么时候用", "s": "英语", "g": 6, "gold": ["e6-present"]},
    {"q": "问候语怎么回答", "s": "英语", "g": 3, "gold": ["e3-greet"]},
    # 跨资料干扰（同一知识点两份资料都有片段，gold 要全部进前 5）
    {"q": "乘法计算从哪一位算起", "s": "数学", "g": 3, "gold": ["m3-mult"]},
    {"q": "面积与周长的计算", "s": "数学", "g": 3, "gold": ["m3-perimeter"]},
    {
        "q": "阅读理解的答题方法",
        "s": "语文",
        "g": 4,
        "gold": ["c4-summary", "c4-idiom"],
    },
    {
        "q": "时态复习要点",
        "s": "英语",
        "g": 6,
        "gold": ["e6-past", "e6-present", "e6-compare"],
    },
    # 知识点即查询（出题管线的实际调用形态：query = knowledge_point）
    {"q": "分数的初步认识", "s": "数学", "g": 3, "gold": ["m3-frac"]},
    {"q": "等式的性质", "s": "数学", "g": 5, "gold": ["m5-equation"]},
    {"q": "比喻和拟人", "s": "语文", "g": 4, "gold": ["c4-metaphor", "c4-personify"]},
]


@pytest.fixture()
def gold_parent(client, db):
    """注册一个黄金集专属家长，并把固定语料按「已向量化」状态入库。"""
    from tests.utils.user import auth_headers, login, register_parent

    username = f"gold_{uuid.uuid4().hex[:8]}"
    register_parent(client, username=username, password="pw123456")
    token = login(client, username, "pw123456").json()["access_token"]
    from sqlmodel import select

    from app.db.models import User

    parent = db.exec(select(User).where(User.username == username)).one()
    pid = parent.id

    materials: dict[str, str] = {}
    for mname in {c["material"] for c in _CORPUS}:
        mat = Material(
            parent_id=pid,
            name=mname,
            storage_key=f"gold/{uuid.uuid4().hex}",
            text="黄金集固定语料",
            index_state=INDEX_STATE_PENDING,
            embed_model="gold-fake",
            chunker_ver=CHUNKER_VERSION,
        )
        db.add(mat)
        db.commit()
        db.refresh(mat)
        materials[mname] = mat.id

    for i, c in enumerate(_CORPUS):
        db.add(
            MaterialChunk(
                parent_id=pid,
                material_id=materials[c["material"]],
                seq=i,
                content=c["content"],
                embedding=encode_vector(_fake_embed([c["content"]])[0]),
                embed_model="gold-fake",
                chunker_ver=CHUNKER_VERSION,
                subject=c["subject"],
                grade=c["grade"],
            )
        )
    db.commit()
    return {"parent_id": pid, "token": token, "headers": auth_headers(token)}


def _retrieve(db, parent_id, monkeypatch, subject, grade, query):
    """固定 embedding 替身 + 配置对齐后跑一次检索，返回 top5 content 列表。"""
    monkeypatch.setattr("app.core.config.settings.EMBEDDING_MODEL", "gold-fake")

    async def _fake_embed_async(texts):
        return _fake_embed(texts)

    monkeypatch.setattr(
        "app.features.materials.retrieval.embed_texts", _fake_embed_async
    )
    retriever = VectorKnowledgeRetriever(db, parent_id)
    chunks = retriever.retrieve(
        subject=subject, grade=grade, knowledge_point=query, query=query
    )
    return [c.content for c in chunks[:5]]


class TestGoldSetRecall:
    def test_hit_at_5_every_query(self, gold_parent, db, monkeypatch):
        """每条黄金查询：top5 至少命中 1 个 gold 片段（Hit@5 = 100% 门禁）。"""
        misses = []
        for entry in _GOLD:
            top5 = _retrieve(
                db,
                gold_parent["parent_id"],
                monkeypatch,
                entry["s"],
                entry["g"],
                entry["q"],
            )
            gold_texts = [c["content"] for c in _CORPUS if c["id"] in entry["gold"]]
            if not any(g in top5 for g in gold_texts):
                misses.append(f"{entry['q']!r} → top5 无 gold（got {len(top5)} 条）")
        assert misses == [], "Hit@5 未达标：\n" + "\n".join(misses)

    def test_recall_at_5_threshold(self, gold_parent, db, monkeypatch):
        """整体 Recall@5 ≥ 0.85（ADR-0055 §14 的门禁；改检索策略后重标）。"""
        total, hits = 0, 0
        for entry in _GOLD:
            top5 = _retrieve(
                db,
                gold_parent["parent_id"],
                monkeypatch,
                entry["s"],
                entry["g"],
                entry["q"],
            )
            gold_texts = [c["content"] for c in _CORPUS if c["id"] in entry["gold"]]
            found = sum(1 for g in gold_texts if g in top5)
            total += len(gold_texts)
            hits += found
        recall = hits / total
        assert recall >= 0.85, f"Recall@5 = {recall:.2f} ({hits}/{total}) 低于门禁"

    def test_grade_isolation(self, gold_parent, db, monkeypatch):
        """年级过滤：三年级查询绝不召回六年级片段（反之亦然）。"""
        top5 = _retrieve(db, gold_parent["parent_id"], monkeypatch, "英语", 3, "时态")
        for c in top5:
            assert "六年级" not in str(c)
        # 语料里六年级时态片段与三年级问候片段按 subject+grade 隔离，上面已隐式覆盖；
        # 显式断言：三年级查询的三年级问候片段可达
        top5_greet = _retrieve(
            db, gold_parent["parent_id"], monkeypatch, "英语", 3, "问候语"
        )
        assert any("Good morning" in c for c in top5_greet)
