"""内置交互讲解场景库（ADR-0073 v3 / ADR-0083）：注册表的身份是**交互外壳**。

为什么是「外壳」而不是「完整 SceneSpec 种子」（ADR-0083 决策 4）：场景数据分三份
各司其职——几何（顶点 + 边）是**每场景自带**的一等字段（源自图库 `figure_library`，
创作画板设计、放置时内联进 SceneSpec），而**交互方式**（对称轴初值、播放/拖动控件、
引导文案）是**按 kind 统一**的。把交互部分收进本注册表，SceneSpec 才能瘦成纯几何。

为什么要有这个模块（而不是继续让默认值散落）：reflection 的交互初值（轴 90°、
位置 0.5、controls、narrative）此前**同时**硬编码在三处——后端
``default_scene_from_figure``、前端 ``ReflectionSceneData`` 的默认值、以及编辑器
手工重建的结构。三份互为镜像，却没有一处被显式命名为「外壳」，于是任何一侧改动
都要靠人肉同步。本模块把它们收拢成唯一一处可引用的定义。

三条边界（改动前必读，违反会静默或直接破坏渲染）：
1. **注册表不是事实源。** 唯一事实源是 ``KnowledgePoint.scenes``；渲染与出题
   只读它，**永不回查**本注册表的外壳以外的内容。正因如此，ADR-0061 §U 的快照
   铁律天然保住：改这里的定义绝不可能影响已落库的 ``Question.scene_spec``。
2. **外壳不含几何。** 这里**没有** ``points`` / ``edges`` / ``figure``——几何一律
   由实例化方（图库兜底 / 教师模板 / 画板）内联进 SceneSpec。预置几何会在「题面
   答不出图形」时退化成「永远给个房子」，用臆造的图形冒充讲解（ADR-0073 决策 6）。
3. **不给结论。** 对称判定改为**纯视觉**（拖轴 + 翻转自演示，ADR-0083 决策 2）：
   外壳不再带 ``outputs.isAxisymmetric`` / ``axis_angles`` / ``axis_count``——那是
   属性判定，会把「它是不是轴对称」替学生答了。``axisAngle`` 只是用户交互的**初值**，
   不是关于图形的断言。
"""
from __future__ import annotations

import copy
from typing import Any

# 首个（当前唯一）内置场景外壳：轴对称演示。
#
# 只声明「怎么交互」：对称轴初值（角度 90°、居中）、控件开关（播放 / 拖动）、
# 中性引导文案。**不含几何**——图形顶点由实例化方内联进 SceneSpec（见边界 2）。
REFLECTION_SHELL: dict[str, Any] = {
    "kind": "reflection",
    # 展示名（场景库清单 / 编辑器 / 课件选择器的标签）。它不是 SceneSpec 字段
    # ——SceneSpec 已无 title（ADR-0083 决策 5）；这里只是 kind 的默认显示名。
    "title": "轴对称演示",
    # 交互参数**初值**（非几何、非断言）：用户运行时拖轴/翻转，不入 SceneSpec。
    "axisAngle": 90.0,
    "axisX": 0.5,
    "axisY": 0.5,
    "controls": {"play": True, "scrub": True},
    # 引导**动手试**而不报答案：说出「有几条」就等于把答案念出来了。
    # 中性文案不含图形名——那时还不知道是哪个图形。
    "narrative": (
        "点播放看沿对称轴对折后两侧能否完全重合；也可以自己旋转、平移对称轴，"
        "找出所有能重合的角度。"
    ),
}

# 注册表本体：键为 kind（稳定契约，只弃用不重命名），值为上述「交互外壳」。
SCENE_LIBRARY: dict[str, dict[str, Any]] = {
    "reflection": REFLECTION_SHELL,
}


def get_builtin_scene(kind: str | None) -> dict[str, Any] | None:
    """取某个内置场景的**交互外壳**（深拷贝），未知 kind 返回 ``None``。

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
    """列出全部内置场景外壳（深拷贝），供编辑器下拉与浏览页枚举。"""
    return [copy.deepcopy(scene) for scene in SCENE_LIBRARY.values()]
