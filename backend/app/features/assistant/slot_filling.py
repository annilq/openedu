"""缺槽预检引擎（ADR-0095）：确定性、无 IO 的纯函数。

输入 = 某业务的 ``input_schema``（manifest 唯一事实源）+ 已持久化的 ``collected``
槽位 + 本轮 ``incoming`` 消息 + ``ctx_extra``（上下文透传）。输出该轮是「澄清」
还是「放行」，以及合并后的完整槽位字典与缺失必填槽清单。

引擎不读 DB、不调模型，全部为规则匹配；加载不同 business 的 schema 互不串
（无任何模块级可变状态）。
"""
from __future__ import annotations

import importlib
import re
from typing import Any

# 内部哨兵：表示本轮未从任何来源抽到该槽（与 ``collected`` 的缺省值区分）。
_MISSING = object()

# 题型中文关键词 → 标准英文码（与 ``question/agent.parse_specs_from_text`` 同源）。
_QTYPE_KEYWORDS: dict[str, str] = {
    "选择": "choice", "单选": "choice", "选择题": "choice", "多选": "choice",
    "填空": "fill", "填空题": "fill",
    "判断": "choice", "判断题": "choice",
    "计算": "calc", "计算题": "calc", "应用题": "calc",
    "问答": "open", "解答": "open", "简答题": "open", "问答题": "open", "解答题": "open",
}
# 学科别名 → 标准名（自由文本容错，复用出题子代理风格）。
_SUBJECT_ALIASES: dict[str, str] = {
    "英文": "英语", "道法": "政治",
}
# 难度中文关键词 → 标准英文码。
_DIFFICULTY_KEYWORDS: dict[str, str] = {
    "简单": "easy", "容易": "easy",
    "中等": "medium", "适中": "medium",
    "难": "hard", "困难": "hard", "难题": "hard",
}
# bool 槽的关键词（出现即视为 True）。
_BOOL_KEYWORDS: dict[str, tuple[str, ...]] = {
    "multi": ("多选", "多选题"),
    "judge": ("判断题", "判断对错", "判断正误"),
    "multi_subject": ("多学科", "组卷", "多学科组卷"),
}
# 中文数字 → 阿拉伯数字（年级抽取用）。
_CN_NUM: dict[str, int] = {
    "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
    "六": 6, "七": 7, "八": 8, "九": 9,
}


def resolve_enum_ref(ref: str) -> list:
    """把 ``"app.domain.subjects.SUBJECTS"`` 解析为具体枚举列表。

    载入时机在 schema 处理期（``importlib.import_module`` + ``getattr``），绝不留成
    字符串——枚举增减只改权威常量一处。无法解析时返回空列表（不抛，纯函数容忍）。
    """
    if not ref or "." not in ref:
        return []
    module_path, attr = ref.rsplit(".", 1)
    try:
        module = importlib.import_module(module_path)
        value = getattr(module, attr)
    except (ModuleNotFoundError, AttributeError):
        return []
    return list(value)


def _effective_enum(slot: dict) -> list:
    """槽位的实际可选项：``enum`` 字面量优先，否则解析 ``enum_ref``。"""
    enum = slot.get("enum")
    if enum:
        return list(enum)
    ref = slot.get("enum_ref")
    if ref:
        return resolve_enum_ref(ref)
    return []


def _matches_type(type_: str, value: Any, slot: dict) -> bool:
    """``ctx.extra`` 透传值是否可安全作为某槽的值（类型 / 枚举 / 范围校验）。

    类型不符则拒绝——避免把 ``knowledge_point`` 这种 ORM 对象当字符串槽值污染
    ``Conversation.slots`` 的 JSON 序列化。
    """
    if value is None:
        return False
    if type_ == "enum":
        return value in _effective_enum(slot)
    if type_ == "int":
        if isinstance(value, bool) or not isinstance(value, int):
            return False
        lo, hi = slot.get("min"), slot.get("max")
        if lo is not None and value < lo:
            return False
        if hi is not None and value > hi:
            return False
        return True
    if type_ == "bool":
        return isinstance(value, bool)
    if type_ == "string":
        return isinstance(value, str)
    return False


def _extract_enum_from_text(name: str, slot: dict, message: str) -> Any:
    # 学科别名 → 标准名（与 parse_specs_from_text 同款容错）
    if name == "subject":
        for alias, std in _SUBJECT_ALIASES.items():
            if alias in message:
                return std
    # 直接子串匹配枚举值（学科等中文枚举天然命中）
    for v in _effective_enum(slot):
        if v and v in message:
            return v
    # 英文码枚举（qtype / difficulty）走中文关键词映射
    if name == "qtype":
        for kw, code in _QTYPE_KEYWORDS.items():
            if kw in message:
                return code
    if name == "difficulty":
        for kw, code in _DIFFICULTY_KEYWORDS.items():
            if kw in message:
                return code
    if name == "semester":
        if "上学期" in message:
            return "上"
        if "下学期" in message:
            return "下"
    return _MISSING


def _in_range(val: int, lo: Any, hi: Any) -> bool:
    """int 槽的范围校验（min/max 缺省即不限）。"""
    return (lo is None or val >= lo) and (hi is None or val <= hi)


def _int_from_group(raw: str) -> int | None:
    """正则捕获组 → int（阿拉伯数字或中文数字）；无法解析返回 None。"""
    if raw.isdigit():
        return int(raw)
    return _CN_NUM.get(raw)


def _extract_int_from_text(name: str, slot: dict, message: str) -> Any:
    """按**槽名**分派 int 抽取：grade 只认「N年级」，count 只认「N道/题/个」。

    grade 与 count 同为 int 但语义互斥：若让年级正则对 count 槽也生效，
    「帮我出 2 道三年级数学选择题」会把年级 3 当作数量（实测多出一道题）。
    故二者必须按 name 分派，绝不能共用同一条正则顺序尝试。
    """
    lo, hi = slot.get("min"), slot.get("max")
    if name == "grade":
        m = re.search(r"(\d)\s*年级", message)
        if not m:
            m = re.search(r"([一二三四五六七八九])\s*年级", message)
        if m:
            val = _int_from_group(m.group(1))
            if val is not None and _in_range(val, lo, hi):
                return val
        return _MISSING
    if name == "count":
        m = re.search(r"(\d+)\s*(道|题|个)", message)
        if not m:
            m = re.search(r"([一二三四五])\s*(道|题)", message)
        if m:
            val = _int_from_group(m.group(1))
            if val is not None and _in_range(val, lo, hi):
                return val
        return _MISSING
    return _MISSING


def _extract_from_text(name: str, type_: str, slot: dict, message: str) -> Any:
    if not message:
        return _MISSING
    if type_ == "enum":
        return _extract_enum_from_text(name, slot, message)
    if type_ == "int":
        return _extract_int_from_text(name, slot, message)
    if type_ == "bool":
        keywords = _BOOL_KEYWORDS.get(name)
        if keywords and any(k in message for k in keywords):
            return True
        return _MISSING
    # string：本设计只从 ctx.extra 透传（source=context/both），不抽自由文本
    return _MISSING


def _extract(slot: dict, message: str, ctx_extra: dict | None) -> Any:
    """按 source 先从文本抽、未命中再尝试上下文透传。"""
    name = slot["name"]
    type_ = slot["type"]
    source = slot.get("source", "text")
    ctx_extra = ctx_extra or {}
    value = _MISSING
    if source in ("text", "both"):
        value = _extract_from_text(name, type_, slot, message)
    if value is _MISSING and source in ("context", "both"):
        cv = ctx_extra.get(name)
        if _matches_type(type_, cv, slot):
            value = cv
    return value


def fill_slots(
    schema: list[dict],
    collected: dict | None,
    *,
    incoming: str,
    ctx_extra: dict | None = None,
) -> dict:
    """确定性缺槽预检核心。

    返回 ``{"extracted", "merged", "missing", "clarifying"}``：
    - ``extracted``：本轮从消息 + 上下文抽到的槽（不含沿用 collected 的部分）。
    - ``merged``：merge(collected, extracted)，extracted 覆盖；optional 回填默认值。
    - ``missing``：必填且仍空（None/""）的槽，每项带 name/prompt/type/enum/min/max。
    - ``clarifying``：有必填缺失时为 True（调用方据此产出澄清帧）。
    """
    collected = collected or {}
    ctx_extra = ctx_extra or {}
    incoming = incoming or ""

    merged: dict[str, Any] = {}
    extracted: dict[str, Any] = {}

    # 1) 先搬已持久化且非空的槽（仅限 schema 内，避免把无关键写进 Conversation.slots）
    for slot in schema:
        name = slot["name"]
        if name in collected and collected[name] not in (None, ""):
            merged[name] = collected[name]

    # 2) 本轮抽取（覆盖）
    for slot in schema:
        name = slot["name"]
        val = _extract(slot, incoming, ctx_extra)
        if val is not _MISSING:
            extracted[name] = val
            merged[name] = val

    # 3) optional 默认值回填（required 无默认，不回填）
    for slot in schema:
        name = slot["name"]
        if slot.get("required"):
            continue
        if name in merged and merged[name] not in (None, ""):
            continue
        default = slot.get("default", "")
        merged[name] = default

    # 4) 计算缺失必填槽
    missing: list[dict] = []
    for slot in schema:
        if not slot.get("required"):
            continue
        name = slot["name"]
        if merged.get(name) in (None, ""):
            missing.append(
                {
                    "name": name,
                    "prompt": slot.get("prompt", ""),
                    "type": slot["type"],
                    "enum": _effective_enum(slot) or None,
                    "min": slot.get("min"),
                    "max": slot.get("max"),
                }
            )

    return {
        "extracted": extracted,
        "merged": merged,
        "missing": missing,
        "clarifying": bool(missing),
    }


def summarize_slots(merged: dict) -> str:
    """生成「已确认规格」汇总文案（覆盖被默认填充的 optional 槽，供用户生成前修正）。"""
    subject = merged.get("subject") or "（未指定）"
    grade = merged.get("grade") or "（未指定）"
    qtype = merged.get("qtype") or "（未指定）"
    count = merged.get("count", 1)
    difficulty = merged.get("difficulty") or "medium"
    kp = merged.get("knowledge_point") or "（未指定）"
    return (
        f"已确认规格：科目={subject} 年级={grade} 题型={qtype} "
        f"数量={count} 难度={difficulty} 知识点={kp}"
    )
