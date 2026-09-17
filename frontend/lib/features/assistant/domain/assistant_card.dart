/// AI 助手卡片协议 v2（ADR-0042）：把 `DATA` 帧解析成**类型化卡片**。
///
/// 线协议形状（与后端 `app/ai/subagents/query/render.py` 的 `Card` 对应）：
///
/// ```
/// DATA { type: <kind>, result: { title, subject, items?, stats?, total?, text?, actions? } }
/// ```
///
/// - [kind] 取自信封的 `data.type`——机器可读的**判别键**，渲染器按它分派；
/// - 其余字段取自 `data.result`——该种类的**结构化载荷**；
/// - [actions] 是该种类可选的**受控跳转出口**（如引导卡的「去布置任务」）。
///
/// v1 把「标签」放在 `data.result.type`，与信封的 `data.type`（种类）同名异义；
/// 前端又只留 `result`，于是既丢了种类、又把标签当标题渲染——「按类型渲染不同卡片」
/// 在那套契约下无从实现（ADR-0042 记录了这次修正）。
///
/// 容错原则：**认不出的载荷不许变成空气泡**。字段全缺时 [hasContent] 为 false，
/// 调用方据此跳过；未知 [kind] 由渲染器的降级卡兜住（见 `assistant_cards.dart`）。
class AssistantCard {
  /// 卡片种类判别键（`task_list` / `wrong_question_list` / `due_review_list` /
  /// `mastery_list` / `child_list` / `progress` / `notice` / `question`）。
  final String kind;

  /// 卡头标签（人可读），如「错题」「今日任务」。
  final String title;

  /// 归属标签，如「小明（2年级）」或「未指派」。
  final String subject;

  /// 结构化明细（列表类卡片）。
  final List<Map<String, dynamic>> items;

  /// 真实命中条数；大于 `items.length` 说明被服务端截断，UI 需补「共 N 条」。
  final int total;

  /// 无结构可言的说明文本（空结果 / 错误）。
  final String text;

  /// 指标类卡片的数值（`progress`：total / correct / accuracy / streak_days / checkin_days）。
  final Map<String, dynamic> stats;

  /// 卡片上的**受控跳转出口**（目前只有引导卡 `guide` 会用）。
  ///
  /// 载荷里给的是 `target`（受控枚举），不是 URL——助手在服务端、导航在客户端，
  /// 且同一个目标在家长端（push 的整页）与娃娃端（壳内页签）落点不同。由
  /// `ShellDestination.fromTarget` 解读，认不出的 target 什么也不做。
  final List<AssistantCardAction> actions;

  /// 原始载荷（`data.result` 原样）。
  ///
  /// 给「载荷字段就是领域字段」的种类用——题目卡（`question`）的载荷是
  /// `asdict(GeneratedQuestion) + reasoning`，字段多且随出题引擎演进，
  /// 逐字段建模不如让渲染器直接读（也不该为它撑大本类）。
  final Map<String, dynamic> rawPayload;

  const AssistantCard({
    required this.kind,
    this.title = '',
    this.subject = '',
    this.items = const <Map<String, dynamic>>[],
    this.total = 0,
    this.text = '',
    this.stats = const <String, dynamic>{},
    this.actions = const <AssistantCardAction>[],
    this.rawPayload = const <String, dynamic>{},
  });

  /// 是否有任何可渲染内容——没有则不要占位（避免空卡片）。
  ///
  /// 只有题目卡会读 [rawPayload]：它的载荷就是领域字段（`stem` / `options` …），
  /// 没有 `title` / `text` 这类通用字段。其余种类若连一个通用字段都没有，
  /// 说明这条帧没有可展示的东西——跳过比画一个空壳好（与 v1 口径一致）。
  ///
  /// [actions] 也算内容：引导卡只有「一句说明 + 一个出口」时，那个出口就是全部价值。
  bool get hasContent =>
      title.isNotEmpty ||
      subject.isNotEmpty ||
      items.isNotEmpty ||
      stats.isNotEmpty ||
      text.isNotEmpty ||
      actions.isNotEmpty ||
      (kind == AssistantCardKind.question && rawPayload.isNotEmpty);

  /// 从 `DATA` 帧的 `data` 载荷解析；不可渲染时返回 null（调用方跳过该帧）。
  ///
  /// `result` 不是对象即视为畸形帧——v1 起就是这个口径，保持不变。
  static AssistantCard? fromData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['result'];
    if (raw is! Map) return null;
    final payload = _asMap(raw);
    return AssistantCard(
      kind: _asString(data['type']),
      title: _asString(payload['title']),
      subject: _asString(payload['subject']),
      items: _asItems(payload['items']),
      total: _asInt(payload['total']),
      text: _asString(payload['text']),
      stats: _asMap(payload['stats']),
      actions: _asActions(payload['actions']),
      rawPayload: payload,
    );
  }

  static String _asString(Object? v) => v == null ? '' : '$v'.trim();

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_asString(v)) ?? 0;
  }

  static Map<String, dynamic> _asMap(Object? v) => v is Map
      ? v.map((k, x) => MapEntry('$k', x))
      : const <String, dynamic>{};

  static List<Map<String, dynamic>> _asItems(Object? v) => v is List
      ? v.whereType<Map>().map(_asMap).toList(growable: false)
      : const <Map<String, dynamic>>[];

  /// 解析 `actions[]`：缺 `label` 或 `target` 的一项**整条丢弃**。
  ///
  /// 半张动作卡（有按钮没落点，或反之）点了只会让人以为界面坏了，不如不显示——
  /// 与「认不出的 kind 也要兜住内容」相反：那边丢的是内容，这边丢的是一个坏交互。
  static List<AssistantCardAction> _asActions(Object? v) => v is List
      ? v
          .whereType<Map>()
          .map(_asMap)
          .map(AssistantCardAction.fromJson)
          .whereType<AssistantCardAction>()
          .toList(growable: false)
      : const <AssistantCardAction>[];
}

/// 卡片上的一个受控跳转动作：显示文案 + 线协议 target。
///
/// [target] 是**受控枚举**（如 `parent_create_task`），不是 URL 也不是路由名——
/// 由 `shared/presentation/shell_navigation.dart#ShellDestination.fromTarget` 解读。
class AssistantCardAction {
  final String label;
  final String target;

  const AssistantCardAction({required this.label, required this.target});

  static AssistantCardAction? fromJson(Map<String, dynamic> v) {
    final label = AssistantCard._asString(v['label']);
    final target = AssistantCard._asString(v['target']);
    if (label.isEmpty || target.isEmpty) return null;
    return AssistantCardAction(label: label, target: target);
  }
}

/// 卡片种类常量（与后端 `render.py#_KIND` 逐字对齐）。
///
/// 用法同 [AssistantEventType]：判别键是线协议的一部分，两端各持一份常量表，
/// 但**只有后端能新增**——前端认不出的种类由降级卡兜住，不会丢内容。
class AssistantCardKind {
  const AssistantCardKind._();

  /// 出题引擎的题目卡（`app/ai/subagents/question/translate.py`）。
  static const question = 'question';

  /// 任务列表（`list_parent_tasks` / `list_today_tasks`）。
  static const taskList = 'task_list';

  /// 错题列表（`list_wrong_questions`）。
  static const wrongQuestionList = 'wrong_question_list';

  /// 待复习列表（`list_due_reviews`）。
  static const dueReviewList = 'due_review_list';

  /// 知识点掌握度（`get_mastery`）。
  static const masteryList = 'mastery_list';

  /// 可查询的娃娃（`list_children`）。
  static const childList = 'child_list';

  /// 学习进度指标（`get_progress`）。
  static const progress = 'progress';

  /// 题库题目列表（`list_bank_questions`，仅家长可见）。
  static const questionBankList = 'question_bank_list';

  /// 任务引导卡（后端 `guide` SubAgent 直接产出，**不来自工具结果**）。
  ///
  /// 它回答的是「你想做的这件事我不做，但出口在这」——载荷是
  /// `{title, text, actions[{label, target}]}`。
  static const guide = 'guide';

  /// 无结构可言的提示（查询失败等）。
  static const notice = 'notice';
}
