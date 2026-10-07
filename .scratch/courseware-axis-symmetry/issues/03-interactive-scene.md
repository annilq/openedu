# 03: 交互场景 reflection 落地

**What to build:** 把课件 `cacb390…` 的环节 1（interactive_scene `reflection`「动手画对称图形」）的 payload 补全为**完整可交互**的轴对称补全场景。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 确认 `payload.inputs.points` 已知点集对称补全后形成合法图形（当前 `[[0.3,0.5],[0.7,0.5],[0.7,0.2],[0.3,0.2]]`，axisAngle=90 垂直轴 → 补全为矩形，复核坐标对称正确）。
- [ ] `payload.outputs` 当前被截断（`completedPo…`），补全为完整契约：至少含 `isAxisymmetric: bool`、`completedPoints: [[x,y],…]`、`symmetricPointCount: int`。
- [ ] `narrative` 与 `script`（"画出下面这个轴对称图形的另一半，并标出对称轴"）对齐，避免图文不一致。
- [ ] `controls`（play/pause/scrub/speed）按演示端 `reflection` 渲染器契约核对可用。
- [ ] 在课件演示端实跑一次：拖/点补全 → 校验 outputs 正确返回。

**验收**
- [ ] `outputs` 字段完整，无截断。
- [ ] 演示端交互一次通过：补全结果几何正确、outputs 与预期一致。
- [ ] 与 ADR-0061 `SceneInterpreter` / `reflection` 场景契约一致（前后端 figure parity 测试不退化）。
