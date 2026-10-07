"""内置交互讲解场景库（ADR-0073 v3）：注册表的身份是**作者辅助库**。

为什么要这个模块（而不是继续让默认值散落）：默认 reflection 的参数（轴 90°、
位置 0.5）原先**同时**硬编码在三处——后端 ``default_scene_from_figure``、前端
``ReflectionSceneData`` 的默认值、以及编辑器 ``_buildSpec`` 手工重建的结构。
三份互为镜像，却没有一处被显式命名为「模板」，于是任何一侧改动都要靠人肉
同步。本模块把它们收拢成唯一一处可引用的定义。

四条边界（改动前必读，违反会静默或直接破坏渲染）：
1. **注册表不是事实源。** 唯一事实源是 ``KnowledgePoint.scenes``；渲染与出题
   只读它，**永不回查**本注册表。正因如此，ADR-0061 §U 的快照铁律天然保住：
   改这里的定义绝不可能影响已落库的 ``Question.scene_spec``。
2. **条目形状 = 标准 SceneSpec**，与前端 ``ReflectionSceneData.fromSpec`` 的解析
   契约逐字段同构：扁平的 ``inputs[{key, label, value, min, max, step, unit}]``。
   不可改写成扁平的 ``{scene_name, list:[{name, value}]}``——前端按 ``key`` 取值，
   换了键名会让所有参数解析为空。
3. **绝不预填 ``figure`` / ``points``**（ADR-0073 决策 6）。那是题面命中图库后
   注入的实例化参数；一旦预填成 ``house``，后端兜底会在「题面答不出图形」时
   退化成「永远给个房子」——用臆造的图形冒充讲解。
4. **不给 ``outputs`` 结论。** ``isAxisymmetric`` 取决于具体图形的 ``axis_count``
   （平行四边形是 False），只有知道图形的实例化方才能算；预置等于替学生答题。
"""
from __future__ import annotations

import copy
from typing import Any

# 首个（当前唯一）内置场景：轴对称演示。
#
# 种子是**中性**的：只给「骨架 + 中性默认参数」，具体图形 / 顶点由实例化方
# 注入（见 module docstring 边界 3）。``figure`` / ``points`` 以空值占位，是为了
# 让 inputs 的键集合保持稳定——前端按 key 取值，键一会多一会少会让 fromSpec
# 的解析出现 None 分支。
REFLECTION_SEED: dict[str, Any] = {
    "kind": "reflection",
    "title": "轴对称演示",
    "inputs": [
        {
            "key": "axisAngle",
            "label": "对称轴角度",
            "value": 90,
            "min": 0,
            "max": 180,
            "step": 1,
            "unit": "度",
        },
        {
            "key": "axisX",
            "label": "对称轴水平",
            "value": 0.5,
            "min": 0.3,
            "max": 0.7,
            "step": 0.01,
            "unit": "比例",
        },
        {
            "key": "axisY",
            "label": "对称轴垂直",
            "value": 0.5,
            "min": 0.3,
            "max": 0.7,
            "step": 0.01,
            "unit": "比例",
        },
        # 空占位（不是 house）：等实例化注入。空串 / 空列表让前端解析出
        # 「还没选图形」而非「看到了一个房子」。
        {"key": "figure", "label": "图形", "value": ""},
        {"key": "points", "label": "顶点", "value": []},
    ],
    "controls": {"play": True, "pause": True, "scrub": True, "speed": True},
    # 引导**动手试**而不报答案：说出「有几条」就等于把答案念出来了。
    # 中性文案不含图形名——那时还不知道是哪个图形（实例化方会覆盖它）。
    "narrative": (
        "点播放看沿对称轴对折后两侧能否完全重合；也可以自己旋转、平移对称轴，"
        "找出所有能重合的角度。"
    ),
    # 刻意留空：结论只能由知道图形的实例化方给（见边界 4）。
    "outputs": {},
    "editable": True,
}

# 注册表本体：键为 kind（稳定契约，只弃用不重命名），值为上述 SceneSpec 种子。
SCENE_LIBRARY: dict[str, dict[str, Any]] = {
    "reflection": REFLECTION_SEED,
}


def get_builtin_scene(kind: str | None) -> dict[str, Any] | None:
    """取某个内置场景的**原始定义**（深拷贝），未知 kind 返回 ``None``。

    返回值已深拷贝：调用方随便改都不会污染注册表本身。这是必须的——注册表是
    进程级共享常量，一处被写脏会让后续每个实例都带上别人的参数，而这类 bug
    只在「第二个知识点」才现形（第一个知识点看起来完全正常）。

    未知 kind 返回 ``None`` 而非兜底到 reflection：ADR-0073 决策要求前端对未
    知场景降级为开发者指引，后端静默替换成别的场景会把这个降级信号吃掉。
    """
    if not kind:
        return None
    raw = SCENE_LIBRARY.get(kind)
    if raw is None:
        return None
    return copy.deepcopy(raw)


def list_builtin_scenes() -> list[dict[str, Any]]:
    """列出全部内置场景定义（深拷贝），供编辑器下拉与浏览页枚举。"""
    return [copy.deepcopy(scene) for scene in SCENE_LIBRARY.values()]


def apply_overrides(
    spec: dict[str, Any] | None,
    overrides: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """用实例参数覆盖场景里的同名 ``inputs[].value``（原地修改并返回）。

    - ``overrides`` 为空 → 原样返回（「纯拷贝」的常见情形）。
    - **允许 override 新增模板里没有的 input**（承袭 ADR-0061 §Q 的教训）：
      ``points`` 常年不在教师配的模板里，若只允许覆盖同名 key，这些覆盖会被
      **静默丢弃**——场景退回默认值，改动不生效且无任何报错。新增项标注
      ``generated=True``，便于将来区分「教师配的」与「本题算出来的」。
    - ``spec`` 为 ``None`` → 返回 ``None``（让调用方免写一层判空）。
    """
    if spec is None:
        return None
    if not overrides:
        return spec
    inputs = spec.get("inputs")
    if not isinstance(inputs, list):
        return spec
    # 逐分支复刻原先散落在 fuse_scene_spec 里的合并语义：**无 key 的字典项也会被
    # 补一个 value**。看着别扭，但那正是既有快照的形状，改成「跳过无 key 项」会
    # 让历史数据与新生成的 dump 出现形状差异，而这种差异只在比对时才炸。
    merged: list[Any] = [
        {
            **inp,
            "value": (
                overrides.get(inp["key"], inp.get("value"))
                if isinstance(inp, dict) and "key" in inp
                else inp.get("value") if isinstance(inp, dict) else inp
            ),
        }
        if isinstance(inp, dict)
        else inp
        for inp in inputs
    ]
    present = {
        inp.get("key")
        for inp in inputs
        if isinstance(inp, dict) and inp.get("key") is not None
    }
    for key, value in overrides.items():
        if key not in present:
            merged.append({"key": key, "value": value, "generated": True})
    spec["inputs"] = merged
    return spec


def instantiate_builtin(
    kind: str | None,
    overrides: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """实例化一个内置场景：取定义 + 注入实例参数，产出**完整 SceneSpec**。

    与图库兜底的关系（ADR-0073 决策 8）：``default_scene_from_figure`` 应当
    **经过这里**拿到结构，而不是自己再拼一份——它就是注册表的一个消费者。
    这样「默认轴 90° / 位置 0.5」只有本文件一处来源，改一处即全局生效。
    """
    spec = get_builtin_scene(kind)
    if spec is None:
        return None
    return apply_overrides(spec, overrides)
