# 08: 系统项收进「我的」

**What to build:** 模型管理与运行轨迹从业务导航移出，收进「我的」页内的系统分区。教师日常导航里只剩教学与备课资源两类，排障视图不再占用每天都要扫过的那片区域。

**Blocked by:** 07（侧栏改名与分组，需要「我的」页内的分区结构）

**Status:** done

## 验收

- [x] 侧栏不再列模型管理与运行轨迹（teacher_destinations 删「系统」组；page_labels 侧栏 11→9）
- [x] 「我的」页内出现系统分区（ProfileScreen `if (user.isTeacher)` 系统分区，含 模型管理/运行轨迹），两个入口顺序稳定、可达
- [x] 从系统分区进入的页面，返回落点是「我的」（home_screen 用 `_go` 入栈 + `_withBackHeader` 返回头走 `_back`）
- [x] 系统分区与「外观」「账号信息」排版语言一致（复用 `_SystemNavRow` → 抽到 system_nav_row.dart，AppFocusableAction + 图标 + 名称 + 右箭头）
- [x] 角色差异：系统分区仅教师可见，学生端不传回调、分区不渲染（不改既有判定）
- [x] widget 测试：两个系统入口可从「我的」到达并返回（teacher_nav_single_source / ai_run_trace 重写入口走「我的」；file_size_guard 通过）

### 落地记录（commit）
- `ce7edf9` feat(frontend): 系统项收进「我的」页内分区（lib：teacher_destinations/profile_screen/system_nav_row/home_screen）
- `98c0905` test(frontend): ticket 08 导航改线测试适配
- 合并 `1b43abc` → integration/nav-ia-review（merge 门禁全绿）

## 纪律

- 只搬入口，不重写这两个页面本身。
- 若某个角色原本依赖侧栏直达做高频排障，先在票里登记再搬——不要静默拿走路径。
