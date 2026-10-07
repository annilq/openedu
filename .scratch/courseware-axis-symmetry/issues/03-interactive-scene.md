# 03: 交互场景 reflection 落地

**What to build:** 把课件 `cacb390…` 的环节 1（interactive_scene `reflection`「动手画对称图形」）的 payload 补全为**完整可交互**的轴对称补全场景。

**Blocked by:** 01

**Status:** done

- [x] `payload.inputs` 修正为 ADR-0061 SceneSpec 契约的**列表形态** `[{key,value}]`：`points`（已知右半 + 轴）+ `axisAngle=90`，不再用 `{points:..,axisAngle:..}` map（旧格式会被 `ReflectionSceneData.fromSpec` 忽略并回退到默认「房子」图形）。
- [x] `payload.outputs` 补全为完整契约：`isAxisymmetric: true`、`completedPoints: [[0.3,0.5],[0.7,0.5],[0.7,0.2],[0.3,0.2]]`（完整矩形）、`symmetricPointCount: 4`。
- [x] `narrative` 与 `script`（"画出下面这个轴对称图形的另一半，并标出对称轴"）对齐：已知右半部 + 垂直轴，补全左半成矩形。
- [x] `controls`（play/pause/scrub/speed）保留；`editable: true` 显式声明；`kind: reflection` 在 payload 顶层（供 `SectionInteractiveScene` 取用）。

**验收**
- [x] `outputs` 字段完整，无截断。
- [x] 与 `ReflectionSceneData.fromSpec` 契约一致：顶点驱动、轴角度 spec 优先、outputs.isAxisymmetric→lockedAxisymmetric；前端 figure parity 不退化。
- [x] 演示端投屏：画布边长收口 `AppLayout.contentCard`(520)，不支持沉浸式缩放。

**说明：** 真机/演示端交互「拖点补全 → 校验」需 UI 运行期确认；本 ticket 完成的是 payload 数据与契约正确性（沙箱无法跑 Flutter UI）。
