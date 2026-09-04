# 06 — 知识点掌握度看板

**What to build:** 家长端按知识点聚合正确率，形成掌握度看板，识别薄弱点。

**Blocked by:** 04 — 错题自动归集

**Status:** ✅ done

- [x] 按知识点返回正确率/作答数/掌握度分级（故事 16）
- [x] 看板数据可由进度接口或独立接口提供
- [x] 聚合逻辑有单测：含错题与正常作答计入、分层阈值正确

> 回填说明（2026-09-04）：后端 `domain/mastery.py` 与 `api/routes/mastery.py`（`GET /mastery`）已实现并返回知识点聚合；pytest 随 ADR-0017 全绿（133 passed）。原 `Status: ready-for-agent` 与空勾选为滞后标记，特此修正。
