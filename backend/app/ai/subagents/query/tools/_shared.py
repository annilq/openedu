"""query SubAgent 工具的共享件：孩子定位与出参投影（ADR-0033 决策 8 / 9）。

两个函数是**机制化**的安全与一致边界，任何查询工具都不得自行重写：

- ``resolve_children`` —— 工具入参 → 目标 ``User`` 列表（含归属/越权校验）；
- ``project_for_role`` —— 出参按 ``ctx.role`` 投影（娃娃端剥掉答案与解析）。

角色来源可信：``ctx.role`` 由 ``/assistant/chat`` 端点从 JWT 解出的 ``user.role`` 写入，
客户端无法伪造；工具 handler 不是 FastAPI 依赖、拿不到 request，只能靠 ``ctx`` 透传，
故「每个工具是否记得用它」由契约测试守护（``tests/ai/test_query_tools_contract.py``）。
"""
from __future__ import annotations

from typing import Any
from uuid import UUID

from sqlmodel import Session

from agent_core.subagent import SubAgentContext
from app.core.errors import AppErrorException
from app.core.guard import require_owned_child
from app.db.models import User
from app.features.children.service import list_children_of

# 娃娃端绝不可见的字段（ADR-008 硬门槛）：答案与解析。
# 契约测试遍历全部工具、跑一遍娃娃视角，断言本集合中的键不出现。
ANSWER_FIELDS: frozenset[str] = frozenset({"answer", "explanation"})

_LOCATOR_DESC = (
    "与 {other} 二选一；不指定时传空字符串，两者都为空＝家长名下全部娃娃 / 娃娃本人。"
)

# 全部查询工具共用的两个定位参数（同一份 schema 片段，保证模型侧描述一致）。
LOCATOR_PROPS: dict[str, Any] = {
    "child_id": {
        "type": "string",
        "description": f"娃娃账号 ID（uuid）。{_LOCATOR_DESC.format(other='child_name')}",
    },
    "child_name": {
        "type": "string",
        "description": f"娃娃昵称（模糊匹配）。{_LOCATOR_DESC.format(other='child_id')}",
    },
}

# ── OpenAI strict 模式下的「必填」陷阱与缺席编码（ADR-0040） ──
#
# genkit_openai 的 ``_get_tools_definition`` 对**每个**工具无条件套
# ``openai.lib._pydantic._ensure_strict_json_schema`` 并打 ``strict: True``；该函数把
# ``required`` 重写为**全部 property**（实现第 57 行
# ``json_schema["required"] = [prop for prop in properties.keys()]``）。
# 于是本文件写的 ``"required": []`` 在 wire 上并不存在——模型被迫为每个参数编一个值。
#
# 实测（deepseek-v4-flash / 真接口）：strict 下 ``list_parent_tasks`` 的入参为
# ``{"child_id": "", "child_name": "", "status": ""}``。此时若某参数的「缺席」没有类型合法的
# 编码，模型只能填非法值 → 收到硬错误 → 反复试探（省略 → 仍被要求必填 → 空串 → 还是错）
# → 撞上 SOP「不重复调用同一个工具」后空转、把调用叙述成文本。
#
# 两条不变量（由 ``tests/ai/test_query_tools_contract.py`` 的行为级守卫测试守住）：
# 1. 每个可省略参数都必须有**类型合法的缺席编码**：字符串用 ``""``，整数用 ``0``；
# 2. 枚举型参数必须把 ``NO_FILTER``（``"all"``）列进 ``enum``，否则模型无合法值可填。
#
# 真机第二例：模型把「没有目标娃娃」写成了**字符串** ``"null"`` 传给 ``child_id``
# （``optional_str`` 的缺席值把文本化的 ``None``/``null`` 一并覆盖，JSON ``null`` 本就是
# ``None``）——两条路径都必须归一到「未提供」，否则模型会拿到 ``child_id 不是合法的 uuid``
# 再试一轮。``"undefined"``/``"nil"`` 是同一类文本化缺席（JS / Ruby 口径），一并收。
UNSET_TOKENS: frozenset[str] = frozenset(
    {"", "all", "any", "*", "none", "null", "nil", "undefined", "unset", "n/a", "na"}
)

# 枚举型可选参数的显式「全部 / 不过滤」取值。
NO_FILTER = "all"


class ToolArgumentError(ValueError):
    """入参不合法 / 目标不存在。

    runtime 会在 ``run_with_tools`` 内捕获并回灌 ``{"error": str(exc)}`` 给模型，
    由模型据实告知用户（「查不到就说查不到，不许估算」），而不是让整条流崩掉。
    """


def optional_str(raw: Any) -> str | None:
    """字符串型可选参数的缺席归一：``None`` / 空白 / ``all`` / ``none``… → ``None``。

    ``None`` 与空字符串在语义上是同一件事（未提供），统一收敛到 ``None``，避免
    「strict 模式替模型补的 ``""``」（以及模型自发填的 ``all``）被当成有意义的过滤值。
    """
    if raw is None:
        return None
    text = str(raw).strip()
    if not text or text.lower() in UNSET_TOKENS:
        return None
    return text


def optional_int(raw: Any, *, name: str) -> int | None:
    """整型可选参数的缺席归一：``None`` / 空串 / ``0`` → ``None``（=不设限）。

    ``0`` 显式表示「不设限」——strict 模式下模型必须填一个整数，没有别的缺席写法。
    负数报错（语义上无意义，且能提示模型填错）。
    """
    if raw is None:
        return None
    if isinstance(raw, str) and not raw.strip():
        return None
    try:
        value = int(raw)
    except (TypeError, ValueError) as exc:
        raise ToolArgumentError(f"{name} 必须是整数，收到：{raw!r}") from exc
    if value < 0:
        raise ToolArgumentError(f"{name} 不能为负数：{raw!r}")
    return value or None


def caller_role(ctx: SubAgentContext) -> str:
    """调用者角色（小写归一），工具据它决定可查范围。"""
    return (ctx.role or "").strip().lower()


def _as_uuid(value: Any, *, field: str, hint: str = "") -> UUID:
    if isinstance(value, UUID):
        return value
    try:
        return UUID(str(value))
    except (ValueError, TypeError, AttributeError) as exc:
        # hint 给模型一条可执行的出路：这类错误回灌后模型要靠自纠才能继续，
        # 光说「不是 uuid」它会换个猜法重试（真机见过连试三轮后放弃）。
        raise ToolArgumentError(f"{field} 不是合法的 uuid：{value!r}{hint}") from exc


def _load_user(session: Session, user_id: UUID, *, message: str) -> User:
    user = session.get(User, user_id)
    if user is None:
        raise ToolArgumentError(message)
    return user


def resolve_parent(*, session: Session, ctx: SubAgentContext) -> User:
    """解析调用者本人（家长视角工具用）：``parent_id`` 由端点写入可信 ``extra``。"""
    raw = (ctx.extra or {}).get("parent_id")
    if not raw:
        raise ToolArgumentError("当前会话缺少家长身份，无法查询。")
    return _load_user(
        session, _as_uuid(raw, field="parent_id"), message="当前家长账号不存在。"
    )


def resolve_children(
    *,
    session: Session,
    ctx: SubAgentContext,
    child_id: Any = None,
    child_name: Any = None,
) -> list[User]:
    """定位本次查询的目标娃娃（含越权校验）。

    - **娃娃**：恒为自己，入参被忽略——杜绝「换个 ``child_id`` 查别人」；
    - **家长**：``child_id`` / ``child_name`` 二选一；都不传＝名下全部娃娃；
      指定了但不在名下 → 抛 ``ToolArgumentError``（不静默返回空，避免模型把
      「你没这个娃」误读成「这个娃没数据」）。

    入参先过 ``optional_str``：空串 / ``all`` / ``none`` 一律视为「未指定」。
    """
    extra: dict[str, Any] = ctx.extra or {}

    # 缺席归一收口在此（全部定位工具的公用入口，ADR-0033 决策 8）：strict 模式会替模型补
    # ``""``，模型也可能自发填 ``all``/``none``；不归一的话它们会被当作 uuid 去解析而报错，
    # 模型随即陷入重试（见本模块顶部「strict 模式下的必填陷阱」）。
    child_id = optional_str(child_id)
    child_name = optional_str(child_name)

    if caller_role(ctx) == "child":
        own_raw = extra.get("child_id")
        if not own_raw:
            raise ToolArgumentError("当前会话缺少娃娃身份，无法查询。")
        own = _load_user(
            session, _as_uuid(own_raw, field="child_id"), message="当前娃娃账号不存在。"
        )
        return [own]

    parent = resolve_parent(session=session, ctx=ctx)
    if child_id:
        try:
            return [
                require_owned_child(
                    session=session,
                    owner_id=parent.id,
                    child_id=_as_uuid(
                        child_id,
                        field="child_id",
                        hint="（按昵称定位请改用 child_name；不指定目标请留空）",
                    ),
                    message="未找到该娃娃，或该娃娃不属于你的账号。",
                )
            ]
        except AppErrorException as exc:
            # 工具层不需要 HTTP 信封语义（code/status），只需把「查不到」如实回灌给模型；
            # 归一为 ToolArgumentError，避免业务异常类型从 REST 层漏进内核调用栈。
            raise ToolArgumentError(str(exc)) from exc

    if child_name:
        keyword = child_name
        hits = [
            c
            for c in list_children_of(session=session, parent_id=parent.id)
            if keyword in (c.display_name or "")
        ]
        if not hits:
            raise ToolArgumentError(f"没有找到昵称含「{keyword}」的娃娃。")
        return hits

    return list_children_of(session=session, parent_id=parent.id)


def project_for_role(payload: Any, role: str) -> Any:
    """按角色投影出参：娃娃端剥掉 ``ANSWER_FIELDS``，其他角色原样返回。

    工具**一律返回全量**（错题恒 ``include_answer=True``），裁剪只在此处发生——
    新增工具忘记裁剪会被契约测试拦下，不靠 review 纪律（ADR-008）。
    """
    if (role or "").strip().lower() != "child":
        return payload
    return _strip_answer_fields(payload)


def _strip_answer_fields(node: Any) -> Any:
    if isinstance(node, dict):
        return {
            k: _strip_answer_fields(v) for k, v in node.items() if k not in ANSWER_FIELDS
        }
    if isinstance(node, list):
        return [_strip_answer_fields(x) for x in node]
    return node


def dump(node: Any) -> Any:
    """ORM / 响应模型 → JSON 友好结构（UUID / datetime → str）。

    ``run_with_tools`` 用 ``json.dumps(result, default=str)`` 落 history，若直接塞
    Pydantic 模型会退化成 Python repr（单引号、不可再解析）——故工具出参必须先 dump。
    """
    if hasattr(node, "model_dump"):
        return node.model_dump(mode="json")
    if isinstance(node, list):
        return [dump(x) for x in node]
    if isinstance(node, dict):
        return {k: dump(v) for k, v in node.items()}
    return node


def child_meta(child: User) -> dict[str, Any]:
    """娃娃的身份摘要（每个分组块都带，供模型消歧与前端卡片展示）。"""
    return {"id": str(child.id), "name": child.display_name, "grade": child.grade}


def child_block(
    child: User, items: list[Any], *, meta: dict[str, Any] | None = None
) -> dict[str, Any]:
    """按娃娃分组的结果块：``{id, name, grade, items, meta}``。"""
    return {**child_meta(child), "items": items, "meta": meta or {}}


def envelope(
    blocks: list[dict[str, Any]], *, unassigned: list[Any] | None = None
) -> dict[str, Any]:
    """统一出参信封（全部查询工具同构，方便模型理解与渲染 hook 展开）。

    - ``children``：按娃娃分组的结果块；
    - ``unassigned_items``：不属于任何娃娃的条目（目前仅「家长未派发的草稿任务」）；
    - ``total_children`` / ``total_items``：命中的娃娃数与条目总数。
    """
    spare = list(unassigned or [])
    return {
        "children": blocks,
        "unassigned_items": spare,
        "total_children": len(blocks),
        "total_items": sum(len(b.get("items") or []) for b in blocks) + len(spare),
    }
