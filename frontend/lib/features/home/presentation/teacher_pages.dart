import '../../../../shared/domain/models/models.dart';

// ---------------------------------------------------------------------------
// 教师端导航状态（ADR-0059）
// ---------------------------------------------------------------------------

/// 教师端页面：导航的**唯一**事实源（ADR-0059）。
///
/// 取代「索引 + 审核 / 编辑覆盖层 + `_showProfile`」三个并列状态——那套写法谁盖谁
/// 要靠每个回调自己记得清理。合成 `sealed` 后：各入口天然互斥、无需优先级裁决；
/// `HomeScreen` 里那个 `switch` 由编译器保证穷尽，漏登记会编译失败。
///
/// 单独成文件（而非留在 `home_screen.dart` 内）：11 个页面类占 ~70 行纯声明，
/// 挤在组合根里会把「页面编排」淹没在类型定义中（ADR-0058 P4）。
/// 代价是它们必须从私有改为公开——私有标识符不能跨 library。
sealed class TeacherPage {
  const TeacherPage();
}

/// 概览。
class OverviewPage extends TeacherPage {
  const OverviewPage();
}

/// 布置任务（生成页）。
class CreateTaskPage extends TeacherPage {
  const CreateTaskPage();
}

/// 任务列表。
///
/// [initialTab] 支持深链：待办卡片点「待审核 / 待派发」进 Tab 0（草稿箱），
/// 点「谁没交」进 Tab 1（进行中）。默认 0。
class TaskListPage extends TeacherPage {
  final int initialTab;

  const TaskListPage({this.initialTab = 0});
}

/// 添加学生（StudentFormScreen 创建态）。
class AddStudentPage extends TeacherPage {
  const AddStudentPage();
}

/// 编辑学生资料（StudentFormScreen 编辑态）。
class EditStudentPage extends TeacherPage {
  final UserModel child;

  const EditStudentPage(this.child);
}

/// 题库。
class QuestionBankPage extends TeacherPage {
  const QuestionBankPage();
}

/// 资料库（教师上传资料 + 向量化，ADR-0055）。
class MaterialLibraryPage extends TeacherPage {
  const MaterialLibraryPage();
}

/// 模型管理。
class ModelsPage extends TeacherPage {
  const ModelsPage();
}

/// 草稿审核。
class TaskReviewPage extends TeacherPage {
  final TaskModel task;

  /// 退出审核后回到的页面——保留「从哪儿进来就回哪儿」的既有行为
  /// （从概览点进来回概览，从任务列表点进来回列表）。
  final TeacherPage back;

  /// 表单布置时带过来的派发目标（ticket 18）：班级 / 学生多选；空 = 回落单学生派发。
  final List<String> classIds;
  final List<String> studentIds;

  const TaskReviewPage(
    this.task, {
    required this.back,
    this.classIds = const [],
    this.studentIds = const [],
  });
}

/// 个人信息（「我的」）。
class ProfilePage extends TeacherPage {
  const ProfilePage();
}

/// 学生详情页页签（局部状态，不提升为全局）。
enum StudentDetailTab { overview, wrongQuestions, tutorLogs }

/// 学生管理页（按班级分组 + 筛选 + 活跃错题数，ADR-0068 §2.3 / ticket 02）。
///
/// 与 [StudentDetailPage] 并列：前者是「全班总览」，后者是「单个学生深耕」。
/// 侧栏「学生」项进入本页（ticket 16 将其与「统计」一同收进八项侧栏）。
class StudentManagementPage extends TeacherPage {
  const StudentManagementPage();
}

/// 学情统计页（作用域三态 + 四维聚合，ticket 12）。
///
/// 侧栏「统计」项进入本页，消费 `/analytics/*` 三个聚合端点。
class AnalyticsPage extends TeacherPage {
  const AnalyticsPage();
}

/// 学生详情页（带学生 ID，不依赖全局选中态）。
///
/// 取代「先选中学生 → 右侧各视图按全局 `selectedStudentProvider` 取数」的写法：
/// 这里把 studentId 作为入参直传，页签切换也只是本页的局部状态，不会污染其他页面的
/// 上下文（ADR-0059 核心教训——避免「看着 A 却按 B 出题」这类漏清 bug）。
///
/// 与 14 协同：侧栏旧入口（顶部学生选择器菜单）已移除（ADR-0070），进入学生改由
/// 学生管理页点学生触发，并把 studentId 作为入参直传（不再写入任何全局选中态）。
class StudentDetailPage extends TeacherPage {
  final String studentId;
  final StudentDetailTab initialTab;

  const StudentDetailPage(this.studentId,
      {this.initialTab = StudentDetailTab.overview});
}

/// 课件中心（侧栏「课件」一级入口，方案A）。列出本教师全部课件，直达编辑 / 讲课。
class CoursewarePage extends TeacherPage {
  const CoursewarePage();
}

/// 场景库（内置交互讲解场景总览，ADR-0073）。
///
/// 列出后端登记的全部内置场景：场景名、引用它的知识点、以及内置实例数量。
/// 这里的「实例」**只认后端内置参考**——题目 / 课件生成出来的 `scene_spec`
/// 快照不进这张清单（ADR-0073 浏览页语义边界）。
class SceneLibraryPage extends TeacherPage {
  const SceneLibraryPage();
}

/// 单个内置场景的详情：列出引用它的全部知识点实例。
///
/// [kind] 直传而非塞进全局选中态——同 [StudentDetailPage] 的做法（ADR-0059），
/// 避免「看着 A 场景却按 B 场景展示」这种漏清 bug。
class SceneLibraryDetailPage extends TeacherPage {
  final String kind;

  const SceneLibraryDetailPage(this.kind);
}

/// 场景编辑器页（ADR-0074 T02）：在场景库详情里点某个关联知识点，经单一 sealed
/// 状态打开，而非 `showDialog` / `Navigator.push` 直接开编辑器（ADR-0059 单一导航状态）。
///
/// 取代知识点行的 `showDialog(KnowledgePointSceneEditor)`：那写法把「当前该看哪个
/// 页面」偷偷变成并列状态，漏清就弹根栈（白屏）。这里编辑器只是 `TeacherPage` 的
/// 一个分支，关闭统一走 [KnowledgePointSceneEditor.onBack]，不裸 `Navigator.pop`。
///
/// [back] 记录从哪儿进来——场景库详情点进来回落 [SceneLibraryDetailPage]，知识点
/// 管理行点进来回落资料库页；由调用方在 `_go` 时填好，编辑器自己不猜来源。
class SceneLibraryEditorPage extends TeacherPage {
  final String kpId;
  final String kpName;
  final String subject;
  final int grade;
  final String semester;
  final List<Map<String, dynamic>>? initialScenes;
  final TeacherPage back;

  const SceneLibraryEditorPage({
    required this.kpId,
    required this.kpName,
    required this.subject,
    required this.grade,
    required this.semester,
    this.initialScenes,
    required this.back,
  });
}

/// 侧栏高亮用的「基础页」：审核页沿用它进来的那一页的高亮。
///
/// 审核不是一个侧栏入口（否则「任务」会在用户从概览进来时错位高亮），而是某一页
/// 的延续，所以高亮取 [back]。
TeacherPage highlightFor(TeacherPage page) =>
    page is TaskReviewPage ? page.back : page;
