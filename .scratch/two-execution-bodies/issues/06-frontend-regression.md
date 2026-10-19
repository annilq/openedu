# 06 · 前端 kind 映射 + 全量回归

Blocked by: 05

## 内容

- `frontend/lib/features/assistant/domain/run_trace.dart`：`runKindLabel` 补
  `tasks`（任务与题库）与 `capability`（能力自述）映射；历史 `question` / `query`
  映射保留（旧数据不回刷）。
- 全量回归：后端 pytest + 前端 `flutter test`（assistant 相关目录）。
- ADR-0098 状态确认「已实现」；INDEX 票状态更新。

## 验收

- 前端测试零新增红；轨迹页对新旧 kind 均有标签。
- 端到端冒烟（dev server + 真机或替身）：出题 / 学情 / 名单 / 元问题 / 超范围五类输入
  路由与帧序列符合 ADR-0098 §2.1。
