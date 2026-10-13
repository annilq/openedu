# Ticket 04 — 修 students_notifier 空字段校验测试的挂起计时器

- **What to build**: 学生表单空字段提交应提示必填错误——这条产品行为当前的测试因挂起计时器而失败，等于没被验证。失败形态：flutter_animate 的 `initState` 起了未 settle 的计时器，测试报 pending timers。本票修好**测试装置**，让原断言稳定通过。
- **Blocked by**: —（无，可立即开始）
- **Status**: done
- **验收清单**:
  - [x] 定位挂起计时器来源（flutter_animate `_AnimateState.initState` → `_restart` 起 timer）后，按项目五坑纪律之一处理：测试环境将动画时长归零 / 显式 settle / reduce-motion 等价处理
  - [x] 原断言恢复：空字段提交 → 必填错误提示出现
  - [x] 单跑该测试文件连跑 3 次均稳定通过（计时器类失败常偶发，一次绿不算数）
  - [x] 全量 `flutter test` 不新增失败：修后既存红应从 3 个降为 2 个（另两个由 02 / 03 负责，本条不越界去修）
  - [x] 遵守测试纪律：不在测试里改 `debugDefaultTargetPlatformOverride` 后不复位；不写截图装置

## 决策锚点

- **这是测试装置坑，不是产品缺陷**：不要改产品代码（表单校验逻辑）去迁就计时器——产品行为本来就是对的，是验证手段坏了。
- **排查顺序**：失败信息是 pending timers 栈，从栈顶的 animate 入口查起，别盲目加 `pumpAndSettle`（项目五坑之一：pumpAndSettle 在特定树上永不 settle，会慢性挂死）。
- **归因前提**：该红在当前 HEAD（`c2d98c2`）干净 worktree 复现，属既存账；本轮判断题重构未触碰 students 区域。
- **与 02 的关系**：同属 students 区域但病灶不同（02 是分层 import 违反，本条是测试装置计时器）——经确认保持独立工单，不合并。
