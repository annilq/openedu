# T10 · 每日 AI 时长与内容范围管控（故事 23/26 / F-306 / AC-306）

> 范围来源：ticket `.scratch/wawa-learning/issues/10-ai-time-limit.md` + PRD 三期 State-driven EARS（"当家长设置了「每日 AI 使用时长上限」且已达上限时，系统应拒绝新的 AI 答疑请求"）。
> 注：原 T09（内容安全层+家长日志）已在 T08 一并落地，本票顺延为编号 T10 的管控能力。

## 目标
家长可按娃娃配置 AI 使用的「每日次数上限 / 每日时长上限 / 内容（学科）范围」；系统在每次答疑前强制校验，超额或越界请求被拒并给出适龄提示。

## 验收（来自 ticket）
- [x] 家长可配置每日 AI 时长上限与内容范围（故事 23/26）→ `PUT /tutor/quota`（整体覆盖；null=清除该项，0=今日禁用）
- [x] 超额或越界时请求被拒并提示 → 学科越界 403、次数/时长达限 429，携带友好文案；前端气泡透出
- [x] 限额与范围 enforcement 有单测 → `tests/domain/test_quota.py`（17 例）+ `tests/api/routes/test_tutor_quota.py`（13 例）

## 实现要点
- **规则层** `domain/quota.py`（纯函数）：`check_quota()` 按 **学科范围 → 次数 → 时长** 顺序判定，返回 `QuotaDecision(allowed, code, message)`；`validate_quota_config()` 校验值域（上限非负、学科 ∈ SUBJECTS、白名单非空）。
- **数据**：`TutorQuota`（child_id 唯一：daily_ask_limit / daily_minutes_limit / allowed_subjects JSON）+ `TutorUsage`（child_id+usage_date 唯一：used_seconds 当日累计）。
- **口径**：次数沿用 `tutor_log` 当日计数（`count_tutor_today`，全局默认 `TUTOR_DAILY_LIMIT=50` 可被按娃配置覆盖）；时长为服务端实测每次答疑耗时（`time.perf_counter`，向上取整秒）累计。
- **路由** `routes/tutor.py`：`/tutor/ask` 前置三重校验（403/429）→ 答疑 → `add_tutor_usage` 累计耗时 → 落日志；新增 `GET/PUT /tutor/quota`、`GET /tutor/usage`（家长 + 越权 403；配置非法 422；娃娃 403）。
- **前端** `features/tutor/`：`TutorQuotaNotifier`（load/save）+ `TutorUsageNotifier`；`tutor_quota_screen`（次数/时长输入 + 学科 FilterChip 多选，ref.listen 首次回填）；`parent_dashboard` 新增「AI 使用管控」区块（配置摘要 + 今日用量 + 设置入口）；`tutorNotifier.ask` 捕获 `AppException` 透出 429/403 提示文案（原为统一"网络异常"）。
- **配套**：`NetworkService.put` 增加 `query` 参数（quota 设置走 `?child_id=`）；conftest 清理列表补 `TutorLog/TutorQuota/TutorUsage`。

## 代码审查修复（general-purpose agent）
1. 并发竞态：`get_or_create_tutor_usage` 改为捕获 IntegrityError 回滚重查（并发首问不再 500）；`add_tutor_usage` 改 SQL 原子自增（`used_seconds = used_seconds + n`，避免读-改-写丢更新）。
2. GET /usage 去写副作用：改只读 `get_tutor_usage_today`，无行按 0 计。
3. subject 归一化：check_quota 前对 `payload.subject.strip()`，防误拦「 数学」这类输入。
4. 前端 provider 改 family（按 childId）：两娃切换不再互串配置/用量。
5. 前端数字输入校验：非空但非法（如 "1O"）不再静默按"不限制"保存，明确提示。
6. 低风险：`usage_date` 默认工厂改 UTC（原 `date.today()` 本地时区）；check-then-act 非原子（极端并发多放行 1~N 次）已在路由注释声明并记入技术债口径；blocked 请求计次/计时的设计意图（防探测）已注释。
7. 文案："默认 50 次"改"按全局默认上限"，避免与 settings 脱钩。

## 测试
- 后端：`tests/domain/test_quota.py`（默认放行/三类拦截/0=禁用/判定顺序/配置校验）、`tests/api/routes/test_tutor_quota.py`（设置-查看-清除/非法 422/越权 403/娃娃 403/学科拦截 403/按娃覆盖全局 429/0 禁用/用量累计与回带限额）。全量 **91 passed + 1 skipped**，ruff 全过。
- 前端：`test/tutor_notifier_test.dart` 新增 quota/usage 组（解析/PUT body 契约/业务错误文案透出）。`flutter analyze` 0 问题、`flutter test` **18 passed**。

## 提交
见 `git log`（feat(backend+frontend): T10 ...）。
