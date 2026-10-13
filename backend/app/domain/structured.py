"""结构化模型产出的读取工具（dict / pydantic / 对象通吃）。

模型结构化产出（``output_schema`` 约束解码）在不同引擎/版本下可能是 ``dict``、pydantic
模型或普通对象。本模块提供**两态统一读取**的最小工具，出题解析与开放题批改共用
（ADR-0031/0032：跨业务共用的小工具下沉到共享内核，而非任何一个业务包）。
"""
from __future__ import annotations

import re
from typing import Annotated, Any

from pydantic import BeforeValidator


def schema_field(obj: Any, name: str, default: Any = None) -> Any:
    """读模型产出字段（兼容 dict 与 pydantic 对象）。"""
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


# 选项标号前缀：可带括号（(A) / （B））/ 字母或数字 + 分隔符（. 、 ： ． ) ]）。
# 只用于「切分」一段被模型揉在一起的选项串，不剥离——前缀由前端按位置重画，
# 且答案字段也带前缀，剥离会破坏判题比对（见 normalize_options）。
_OPTION_LABEL = re.compile(r"[\(（\[]?[A-Ea-e\d][\)）\].、：:．]\s*")


def _split_options(text: str) -> list[str]:
    """把一段可能揉了多个选项的文本切成「每个选项一段」。

    模型偶发不遵守 output_schema，把全部选项塞进一个字符串或某个列表元素：
    ``"A. 平行四边形 B. 等腰三角形 C. 任意梯形 D. 一般四边形"``。仅当找到 **≥2 个**
    选项标号时才切（避免把正文中偶然出现的「1. 」误拆），单标号或零标号原样返回。
    """
    labels = list(_OPTION_LABEL.finditer(text))
    if len(labels) < 2:
        return [text]
    out: list[str] = []
    for i, m in enumerate(labels):
        end = labels[i + 1].start() if i + 1 < len(labels) else len(text)
        piece = text[m.start():end].strip()
        if piece:
            out.append(piece)
    return out


def normalize_options(raw: object) -> list[dict] | None:
    """把模型产出的 ``options`` 归一为「选项对象」列表（ADR-0089 决策 2）。

    选项对象形状：``{"text": str, "figure_key": str | None}``。

    - ``text``：选项文字，**作答与评分的唯一依据**，恒存在且保留前缀（"A."）。
    - ``figure_key``：图形**身份键**（只给键，不给顶点）；模型没给则为 ``None``。
      顶点由后端在落库前按图库盖章（``figure_stamp``），**模型绝不产出顶点**。

    处理三种畸形输入（均来自模型不守 output_schema）：
    - ``None`` / 非 list 非 str → 返回 ``None``（上层按「无选项」处理）；
    - 单个字符串（可能揉了多个选项）→ 切分；
    - list，元素为 ``str``（可能揉多个选项 → 再切分展平）或 ``dict``
      （``{text, figure}`` / ``{text, figure_key}``，**tolerant read** 兼容旧形与模型异形）。

    **只切分、不剥字母前缀**：前缀（"A."）由前端 ``cleanOptionText`` 按位置重画，
    且答案字段也带前缀，剥离会让判题比对失配。切分后每个选项仍保留自己的前缀。
    """
    if raw is None:
        return None
    if isinstance(raw, str):
        parts: list[object] = [raw]
    elif isinstance(raw, list):
        parts = list(raw)
    else:
        return None

    out: list[dict] = []
    for el in parts:
        if not isinstance(el, (str, dict)) and hasattr(el, "model_dump"):
            # output_schema 约束解码可能给出 pydantic 对象而非 dict。
            el = el.model_dump()
        if isinstance(el, dict):
            # tolerant read：已被结构化（或存量旧列）的选项对象，原样收 shape。
            text = el.get("text")
            text = "" if text is None else str(text).strip()
            if not text:
                continue
            out.append({"text": text, "figure_key": _figure_key_of(el)})
            continue
        p = "" if el is None else str(el).strip()
        if not p:
            continue
        # 单元素若只含一个标号（已经是干净的一项）→ 保留；含多个标号 → 展平。
        for piece in _split_options(p):
            out.append({"text": piece, "figure_key": None})
    return out or None


def option_texts(options: object) -> list[str]:
    """从选项列表取**纯文字**（判题 / 提示词 / 展示与比对用）。

    容错：``dict`` 元素取 ``text``，``str`` 元素原样返回；非 list → 空列表。
    判题路径**只认文字**——图形是展示层的事，不参与比对。
    """
    if not isinstance(options, list):
        return []
    out: list[str] = []
    for o in options:
        if not isinstance(o, (str, dict)) and hasattr(o, "model_dump"):
            o = o.model_dump()
        if isinstance(o, dict):
            text = o.get("text")
            out.append("" if text is None else str(text))
        elif o is not None:
            out.append(str(o))
    return out


def _figure_key_of(el: dict) -> str | None:
    """从选项对象里读图形身份键（``figure.key`` / ``figure`` 字符串 / ``figure_key``）。"""
    figure = el.get("figure")
    if isinstance(figure, dict):
        key = figure.get("key")
        return key.strip() if isinstance(key, str) and key.strip() else None
    if isinstance(figure, str) and figure.strip():
        return figure.strip()
    key = el.get("figure_key")
    return key.strip() if isinstance(key, str) and key.strip() else None


def read_options(raw: object) -> list[dict] | None:
    """**读路径**的容错投影（ADR-0089 决策 2）：存量旧形 ``str`` → ``{text, figure: None}``。

    与 :func:`normalize_options`（**写路径**：切分模型畸形输出、剥出身份键）不同，
    本函数**只做形状迁移**，不做任何清洗：

    - 已是选项对象 → **原样保留**（含内联 ``figure`` 几何，不补顶点、不丢字段）；
    - 存量 ``str`` 元素 → 包成 ``{text, figure: None}``（同一 JSON 列，无 DDL 迁移）；
    - 非 list → ``None``。

    用作 pydantic ``BeforeValidator``，让所有下发端点对存量数据一次性容错。
    """
    if not isinstance(raw, list):
        return None
    out: list[dict] = []
    for el in raw:
        if not isinstance(el, (str, dict)) and hasattr(el, "model_dump"):
            el = el.model_dump()
        if isinstance(el, dict):
            text = el.get("text")
            out.append(
                {
                    "text": "" if text is None else str(text),
                    "figure": el.get("figure"),
                }
            )
        elif el is not None:
            out.append({"text": str(el), "figure": None})
    return out or None


# 响应 schema 的选项字段类型：落库/存量形状 → 选项对象列表（读路径容错）。
# ADR-0089：同一 JSON 列，元素由 str 变对象，**无 DDL 迁移**，靠这层一次性过渡。
OptionList = Annotated[list[dict] | None, BeforeValidator(read_options)]


def coerce_dict(obj: Any) -> dict:
    """把结构化产出归一为 ``dict``（dict / pydantic model_dump / 可迭代键值）。"""
    if obj is None:
        return {}
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "model_dump"):
        return obj.model_dump()
    try:
        return dict(obj)
    except (TypeError, ValueError):
        return {}
