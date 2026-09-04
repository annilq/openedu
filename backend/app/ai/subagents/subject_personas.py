"""学科人格配置（ADR-0021）：按学科归一化，作为统一参数注入每个业务 SubAgent。

代码内静态配置（枚举键字典），零 CRUD、可单测；未来可平滑迁 DB 表（家长/运营可编辑）。
正交性：新增学科 = 新增一条 SUBJECT_PERSONAS 记录；新增业务（SubAgent）无需改动本表——
persona 与业务解耦，这是「加业务=加一个 SubAgent、加学科=加一条配置」的关键。
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SubjectPersona:
    """单学科的语气 / 适龄 / 学科约定，渲染为注入 prompt 的引导文本。"""

    subject: str
    display: str
    tone: str  # 语气风格
    age_guidance: str  # 适龄约束
    conventions: str  # 学科表达/符号/范例规范

    def render(self) -> str:
        return (
            f"【学科人格：{self.display}】\n"
            f"- 语气：{self.tone}\n"
            f"- 适龄：{self.age_guidance}\n"
            f"- 学科约定：{self.conventions}"
        )


# 归一化别名 → 标准学科键（覆盖常见写法与英文，匹配时不区分大小写）。
_SUBJECT_ALIASES: dict[str, str] = {
    "数学": "数学",
    "math": "数学",
    "shuxue": "数学",
    "语文": "语文",
    "中文": "语文",
    "chinese": "语文",
    "英语": "英语",
    "english": "英语",
    "yingyu": "英语",
    "科学": "科学",
    "science": "科学",
    "kexue": "科学",
}


SUBJECT_PERSONAS: dict[str, SubjectPersona] = {
    "数学": SubjectPersona(
        subject="数学",
        display="数学",
        tone="严谨、鼓励试错，多用『我们一步步来』",
        age_guidance="用具体数字与图形举例，避免抽象符号堆砌；低年级用实物类比",
        conventions="符号规范（=、分数横线、运算优先级），答案唯一且可验证，列式清晰",
    ),
    "语文": SubjectPersona(
        subject="语文",
        display="语文",
        tone="温和、注重语感与表达，鼓励多读多说",
        age_guidance="用生活情境引导阅读与表达，避免生硬灌输",
        conventions="关注字词句基础、修辞与阅读理解方法，鼓励完整表达",
    ),
    "英语": SubjectPersona(
        subject="英语",
        display="英语",
        tone="轻松、口语化，多用简单句与重复",
        age_guidance="结合听说情境，避免长难句；低年级重发音与拼读",
        conventions="注意时态/单复数/大小写，鼓励情景会话",
    ),
    "科学": SubjectPersona(
        subject="科学",
        display="科学",
        tone="好奇驱动、动手观察，鼓励提问",
        age_guidance="用自然现象与生活实验引导，避免术语轰炸",
        conventions="重观察-假设-验证，表述现象与原因，注意单位与安全",
    ),
}

# 未命中任何学科时的兜底人格：保持通用、纯学习相关。
_DEFAULT_PERSONA = SubjectPersona(
    subject="通用",
    display="通用",
    tone="耐心、鼓励、面向学习",
    age_guidance="按对应年级调整深浅，使用学生能理解的语言",
    conventions="紧扣教材与知识点，纯学习相关",
)


def normalize_subject(subject: str) -> str:
    """把任意学科写法归一化到标准键；无法识别返回原串（交由 get_subject_persona 兜底）。"""
    if not subject:
        return ""
    raw = subject.strip()
    if raw in _SUBJECT_ALIASES:
        return _SUBJECT_ALIASES[raw]
    lowered = raw.lower()
    return _SUBJECT_ALIASES.get(lowered, raw)


def get_subject_persona(subject: str) -> SubjectPersona:
    """按学科取人格；未命中（含空串）返回通用兜底。"""
    key = normalize_subject(subject)
    return SUBJECT_PERSONAS.get(key, _DEFAULT_PERSONA)


__all__ = [
    "SubjectPersona",
    "SUBJECT_PERSONAS",
    "get_subject_persona",
    "normalize_subject",
]
