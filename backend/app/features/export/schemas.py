"""打印导出的请求 schema（ADR-0052）。

响应不是 schema——端点直接返回 ``application/pdf`` 二进制，客户端不解释服务端模板。
"""

from typing import Literal
from uuid import UUID

from sqlmodel import SQLModel

ExportSource = Literal["bank", "task", "wrong_book"]


class ExportSheetReq(SQLModel):
    """一次打印导出的输入：**单一来源** + 该来源的选题。

    - ``source=bank``：``ids`` 是题目 id（必须全部属于当前家长）。
    - ``source=task``：``ids`` 是任务 id（展开为 ``TaskQuestion`` 深拷贝快照）。
    - ``source=wrong_book``：``child_id`` 必填（错题挂在儿童账户下），
      ``ids`` 可为空 = 该娃娃全部未毕业错题；``due_only=True`` = 只看今天到期。
    """

    source: ExportSource
    ids: list[UUID] = []
    child_id: UUID | None = None
    due_only: bool = False
    # 缺省由服务端按来源推导（单任务=任务名、题库=「{学科} · 练习」等）
    title: str | None = None
