# Ticket 06 — 端到端回归与全量测试（analyze/test + 年级回归）

- **What to build**: 汇总 ticket 02/03/04/05/06 的验收，跑前端 `flutter analyze` + `flutter test`（**先关代理**）与后端 `ruff check` + `pytest`（沙盒 `--basetemp` 指向新目录），确认 0 回归；补年级全链路回归断言。
- **Blocked by**: 03, 04, 05, 06
- **Status**: done
- **验收清单**:
  - 前端 `flutter analyze` 认 `No issues found!`；`flutter test` 全绿（先 `no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同` 关代理，否则 WebSocket 升级报错）。
  - 后端 `cd backend` 后 `ruff check .` 0 issue、`pytest -q --basetemp=/tmp/<新目录>` 0 失败；跑前 `mv .env .env.hidden`、完恢复。
  - 端点级（前端打 REST，「下发了 X」必须打到端点验）：`POST /classes` 后 `GET /classes` 见人数；班内导入后 `GET /students?class_id=` 查到且 `username` 可登录；`POST /students` 带 `class_id` 后该生 `class_id` 落库。
  - 年级回归：加入班级后消费方经 `user.class_id` 解析的年级 `== class.grade`；移出班级后 `class_id` 为空、年级解析为 0、不报错。
  - 原「学生管理」扁平视图与未分班分组观感一字不变。
  - 文件规模棘轮：本轮所有新增/改动文件过 `test/file_size_guard_test.dart` 基线（只许下调）。
