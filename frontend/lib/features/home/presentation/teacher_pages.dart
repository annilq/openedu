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

/// 发布任务（生成页，从「任务」页进入）。
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
///
/// [classId]/[className] 非空表示由班级下钻页发起（ADR-0086 ticket 06）：新建学生
/// 直接归入该班，保存后回落该班下钻页而非概览。
class AddStudentPage extends TeacherPage {
  final String? classId;
  final String? className;
  const AddStudentPage({this.classId, this.className});
}

/// 编辑学生资料（StudentFormScreen 编辑态）。
///
/// 不带回落目标：退出编辑回到哪儿由壳的历史栈决定（`teacher_nav_stack.dart`）。
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

  /// 表单布置时带过来的派发目标（ticket 18）：班级 / 学生多选；空 = 回落单学生派发。
  final List<String> classIds;
  final List<String> studentIds;

  const TaskReviewPage(
    this.task, {
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

/// 学生与班级合并入口（ticket 10）：侧栏只保留一个承载学生的入口「班级」，页内
/// 分「按班级 / 全部学生」两种视图。视图态由 `studentsEntryViewProvider` 持有
/// （见 `students_container_screen.dart`），**不在导航页面对象上**——切页内 tab
/// 不触发壳内换页转场（ticket 05）、下钻返回也能还原，且不污染 ADR-0059 单一状态。
enum StudentsView {
  /// 按班级：班级卡片列表（容器视角）。
  byClass,
  /// 全部学生：跨班扁平列表（内容视角）。
  all,
}

/// 合并后的学生入口（原「学生」+「班级管理」）。
///
/// 它只是壳内一个页；页内两种视图由 [StudentsScreen] 经 `studentsEntryViewProvider`
/// 切换，下钻（班级卡片 → 班内学生 / 列表 → 学生详情）仍走 `_go` 入栈，返回落点由
/// 历史栈决定（ticket 03），本页零义务。
class StudentsPage extends TeacherPage {
  const StudentsPage();
}

/// 学生详情页（带学生 ID，不依赖全局选中态）。
///
/// 取代「先选中学生 → 右侧各视图按全局 `selectedStudentProvider` 取数」的写法：
/// 这里把 studentId 作为入参直传，页签切换也只是本页的局部状态，不会污染其他页面的
/// 上下文（ADR-0059 核心教训——避免「看着 A 却按 B 出题」这类漏清 bug）。
///
/// 与 14 协同：侧栏旧入口（顶部学生选择器菜单）已移除（ADR-0070），进入学生改由
/// 学生管理页点学生触发，并把 studentId 作为入参直传（不再写入任何全局选中态）。
///
/// 不带回落目标：返回落点由壳的历史栈决定，详情页自身不猜来源。
class StudentDetailPage extends TeacherPage {
  final String studentId;
  final StudentDetailTab initialTab;

  const StudentDetailPage(
    this.studentId, {
    this.initialTab = StudentDetailTab.overview,
  });
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

/// 素材库（ADR-0076）：教师自传图片的集中管理入口。多选上传 / grid 陈列 /
/// 点缩略图放大 / 逐张删除；课件环节「添加素材」复用的 [showAssetLibraryPicker]
/// 与这里共用同一份素材库数据。
class AssetLibraryPage extends TeacherPage {
  const AssetLibraryPage();
}

/// 班级下钻页（ADR-0086 / ticket 10）：从合并入口「班级」的「按班级」视图点某班级卡片
/// 进入，复用既有 [StudentManagementScreen]（以 `classId` 参数化），展示只属于该班的学生。
///
/// 与 [StudentDetailPage] 同构：classId / className 直传，不写入任何全局选中态
/// （避免「看着 A 班却显示 B 班」这类漏清 bug）。返回统一回「按班级」列表视图。
class ClassStudentsPage extends TeacherPage {
  final String classId;
  final String className;

  const ClassStudentsPage(this.classId, this.className);
}

/// 运行轨迹列表（ADR-0088 ticket 02）：一次 AI 运行 = 一行，点开看全步骤。
///
/// 与助手页内的「历史会话」是**并列的两个消费者**：历史会话是气泡口径
/// （使用者视角，剥离内部步骤），本页是全步骤 + 元数据口径（审计 / 排障视角）。
/// 同一张后端 `Conversation`/`Message` 表、两种投影、两个入口——刻意不合成一个
/// 「会话详情」，否则教师会在聊天的上下文里读到路由决策与工具载荷。
class RunTracePage extends TeacherPage {
  const RunTracePage();
}

/// 一次运行的全步骤详情：[RunTracePage] 的下钻。
///
/// [runId] 直传而非塞进全局选中态——同 [StudentDetailPage] 的做法（ADR-0059），
/// 避免「看着 A 运行却展示 B 运行」这类漏清 bug。返回统一回列表页。
class RunTraceDetailPage extends TeacherPage {
  final String runId;

  const RunTraceDetailPage(this.runId);
}

// ---------------------------------------------------------------------------
// 页面路径序列化（ticket 12，ADR-0059）
// ---------------------------------------------------------------------------
//
// 把「当前在哪个教师页」序列化成一条稳定字符串，用于进程被回收 / 应用重启后回到同一页
// （审核草稿审到一半被打断，回来还在那一页）。路径**只**用于持久化与恢复，不是跨页
// 通信通道（那有既有的意图通道）。只恢复「在哪一页」，不恢复页内临时输入态。
//
// 还原纪律（见 issue 12）：
// - 认不出的类型或参数缺失 → 一律回落 [OverviewPage]（不崩、不停空白页、不静默半截）。
// - [EditStudentPage] 持有复杂 [UserModel]，不持久化对象本身；以 studentId 落点还原到
//   [StudentDetailPage]（详情页按 id 自取数，安全）。
// - [TaskReviewPage] 是近提交态，刻意不复活（避免陈旧草稿 / 半提交态）；以 taskId 标记，
//   还原时回落 [TaskListPage]。

String _pathWithQuery(String name, Map<String, String> params) {
  if (params.isEmpty) return name;
  final query = params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return '$name?$query';
}

/// 教师页 → 稳定路径字符串。
extension TeacherPagePath on TeacherPage {
  String toPath() {
    final p = this;
    if (p is OverviewPage) return 'overview';
    if (p is CreateTaskPage) return 'create';
    if (p is TaskListPage) return 'tasks?tab=${p.initialTab}';
    if (p is AddStudentPage) {
      return _pathWithQuery('add-student', {
        if (p.classId != null) 'classId': p.classId!,
        if (p.className != null) 'className': p.className!,
      });
    }
    if (p is EditStudentPage) {
      // 编辑页持有复杂对象，不持久化对象本身；见 fromPath 以 studentId 落点还原。
      return _pathWithQuery('edit-student', {'studentId': p.child.id});
    }
    if (p is QuestionBankPage) return 'question-bank';
    if (p is MaterialLibraryPage) return 'material-library';
    if (p is ModelsPage) return 'models';
    if (p is TaskReviewPage) {
      // 近提交态不予复活；见 fromPath 还原到任务列表。
      return _pathWithQuery('review', {'taskId': p.task.id});
    }
    if (p is ProfilePage) return 'profile';
    if (p is StudentsPage) return 'students';
    if (p is StudentDetailPage) {
      return _pathWithQuery('student-detail', {
        'studentId': p.studentId,
        'tab': p.initialTab.name,
      });
    }
    if (p is CoursewarePage) return 'courseware';
    if (p is SceneLibraryPage) return 'scene-library';
    if (p is SceneLibraryDetailPage) {
      return _pathWithQuery('scene-detail', {'kind': p.kind});
    }
    if (p is AssetLibraryPage) return 'asset-library';
    if (p is ClassStudentsPage) {
      return _pathWithQuery('class-students', {
        'classId': p.classId,
        'className': p.className,
      });
    }
    if (p is RunTracePage) return 'run-trace';
    if (p is RunTraceDetailPage) {
      return _pathWithQuery('run-trace-detail', {'runId': p.runId});
    }
    // sealed 穷尽：编译器保证不会漏；兜底概览路径（理论上不可达）。
    return 'overview';
  }
}

/// 路径字符串 → 教师页；认不出 / 参数缺失一律回落 [OverviewPage]。
TeacherPage teacherPageFromPath(String path) {
  final sep = path.indexOf('?');
  final name = sep < 0 ? path : path.substring(0, sep);
  final query = sep < 0
      ? const <String, String>{}
      : Uri.splitQueryString(path.substring(sep + 1));

  TeacherPage decoded = const OverviewPage();
  switch (name) {
    case 'overview':
      decoded = const OverviewPage();
    case 'create':
      decoded = const CreateTaskPage();
    case 'tasks':
      final tab = int.tryParse(query['tab'] ?? '0') ?? 0;
      decoded = TaskListPage(initialTab: tab);
    case 'add-student':
      decoded = AddStudentPage(
        classId: query['classId'],
        className: query['className'],
      );
    case 'edit-student':
      // 还原到详情页（按 id 自取数），而非复活编辑表单。
      final id = query['studentId'];
      decoded = id != null
          ? StudentDetailPage(id, initialTab: StudentDetailTab.overview)
          : const OverviewPage();
    case 'question-bank':
      decoded = const QuestionBankPage();
    case 'material-library':
      decoded = const MaterialLibraryPage();
    case 'models':
      decoded = const ModelsPage();
    case 'review':
      // 近提交态不予复活；回落任务列表（见 toPath 注释）。
      decoded = const TaskListPage();
    case 'profile':
      decoded = const ProfilePage();
    case 'students':
      decoded = const StudentsPage();
    case 'student-detail':
      final id = query['studentId'];
      if (id == null) {
        decoded = const OverviewPage();
        break;
      }
      final tab = StudentDetailTab.values.asNameMap()[query['tab']] ??
          StudentDetailTab.overview;
      decoded = StudentDetailPage(id, initialTab: tab);
    case 'courseware':
      decoded = const CoursewarePage();
    case 'scene-library':
      decoded = const SceneLibraryPage();
    case 'scene-detail':
      final kind = query['kind'];
      decoded = kind != null && kind.isNotEmpty
          ? SceneLibraryDetailPage(kind)
          : const OverviewPage();
    case 'asset-library':
      decoded = const AssetLibraryPage();
    case 'class-students':
      final id = query['classId'];
      final cname = query['className'];
      decoded = id != null && cname != null
          ? ClassStudentsPage(id, cname)
          : const OverviewPage();
    case 'run-trace':
      decoded = const RunTracePage();
    case 'run-trace-detail':
      final runId = query['runId'];
      decoded = runId != null && runId.isNotEmpty
          ? RunTraceDetailPage(runId)
          : const OverviewPage();
    default:
      decoded = const OverviewPage();
  }
  return decoded;
}

/// 侧栏高亮用的「基础页」：审核页沿用**它在栈里的上一层**的高亮。
///
/// 审核不是一个侧栏入口（否则「任务」会在教师从概览进来时错位高亮），而是某一页的
/// 延续。以前这个关系由调用方在创建审核页时手工填 `back` 字段（ticket 03 已移除），
/// 现在由壳把 [parent]（历史栈的上一层）传进来——来源只有一个，不会填错。
///
/// 其余页面高亮自身：下钻页（班级学生 / 学生详情）匹配不到任何侧栏
/// 项 → 侧栏零高亮，这正是「drill-down 不是一级入口」的界面表达。
TeacherPage highlightFor(TeacherPage page, {TeacherPage? parent}) {
  // 「发布任务」已收进「任务」页（方案 A）：生成页是任务页的一个动作态，不是独立侧栏
  // 入口，故它归入「任务」高亮。
  if (page is CreateTaskPage) return const TaskListPage();
  if (page is TaskReviewPage) return parent ?? page;
  return page;
}
