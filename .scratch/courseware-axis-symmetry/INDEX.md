# 课件内容填充 · 图形的运动（轴对称）· Tickets 索引

> 目标：把已存在的草稿课件 `cacb390ee6da4ac0bbe138402950a99e`（知识点 `图形的运动（轴对称）`，数学·四年级·下学期，kp=`357dd9129061452ea9ec35a881548f9c`）从「占位骨架」填充成「可上台」的实课件。
> 现状：4 环节（media_gallery / interactive_scene / practice / media_gallery）内容已填充完成，占位字样清零，`interactive_scene` 的 `outputs` 已补全，CC0 素材落 `coursewareasset` 并改走 `seed_cc0.py` manifest 复现。状态 `ready`（已置，可上台）。
> 发布形式：本地 `.scratch` 文件（未建 GitHub issue）。`gh auth login` 后可一键转 issue。
> 术语以 `CONTEXT.md` 为准；每个 ticket 含 `What to build` / `Blocked by` / `Status: ready-for-agent` / 验收清单。

## 依赖链

```
01 课标对齐与内容大纲 ──────────（无前置）✅ done（内容已产出，供 02–04 引用）
02 素材册两环节（观察 + 探索）落地 ─ 01 ✅ done
03 交互场景 reflection 落地 ────── 01 ✅ done
04 课堂练习 practice 落地 ─────── 01 ✅ done（⚠ 静态题存 payload.questions，直播练习仍走 AI 出题）
05 串联校验 + 状态置 ready + CC0 入库 ─ 02, 03, 04 ✅ done
```

## 范围说明
- 本 epic 是**纯内容填充**，不碰课件编辑器（编辑器能力见 `courseware-round-2`）。
- 素材走 CC0 公共素材库（ADR-0067 §3.5·§5 / T08）：需要真实图时优先引用 `platform_cc0` 预置素材，避免「教师可上传」占位。
- 所有改动落在课件 `sections` 字段（整体覆盖写），不动数据模型。

## 转 GitHub issue 步骤（待登录）
1. `gh auth login`
2. 按编号顺序逐张建 issue，`Blocked by` 指向 blocking issue 编号
3. 全部打 `ready-for-agent` 标签
