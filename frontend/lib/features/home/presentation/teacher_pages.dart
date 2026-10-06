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
class TaskListPage extends TeacherPage {
  const TaskListPage();
}

/// 错题本。
class WrongQuestionsPage extends TeacherPage {
  const WrongQuestionsPage();
}

/// AI 答疑记录。
class TutorLogsPage extends TeacherPage {
  const TutorLogsPage();
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

  const TaskReviewPage(this.task, {required this.back});
}

/// 个人信息（「我的」）。
class ProfilePage extends TeacherPage {
  const ProfilePage();
}

/// 侧栏高亮用的「基础页」：审核页沿用它进来的那一页的高亮。
///
/// 审核不是一个侧栏入口（否则「任务」会在用户从概览进来时错位高亮），而是某一页
/// 的延续，所以高亮取 [back]。
TeacherPage highlightFor(TeacherPage page) =>
    page is TaskReviewPage ? page.back : page;
