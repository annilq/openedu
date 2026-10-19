import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/presentation/shell_navigation.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_content_frame.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../domain/assistant_card.dart';
import 'package:kids_learn/shared/domain/models/assistant_courseware_context.dart';
import '../../domain/conversation.dart';
import '../../providers/assistant_provider.dart';
import '../widgets/assistant_suggested_actions.dart';
import '../provider/assistant_notifier.dart';
import '../provider/conversation_history_provider.dart';
import '../widgets/assistant_hint_card.dart';
import '../widgets/assistant_history_view.dart';
import '../widgets/assistant_input_bar.dart';
import '../widgets/assistant_message_list.dart';
import '../conversation_transcript.dart';
import '../../../../shared/widgets/app_actions.dart';

/// AI 单入口整页形态（ADR-0036 / ADR-0047）：**双端唯一的助手页面**。
///
/// 教师端与学生端都通过右下角浮动按钮（[FloatingAssistant]）push 本整页进入
/// （[showBack] = true）；学生端不再有独立页签入口（统一为浮球，ADR-0036/0047）。
///
/// 两端共用同一 [assistantNotifierProvider] 与同一 [AssistantMessageList]——同一个 AI
/// 能力、同一份会话、同一套渲染，只用 [isTeacher] 切换标题与空态引导的口径。
///
/// 本页经 `Navigator.push` 打开（双端浮球入口），此时它**不在导航壳的宽度兜底范围内**
/// （ADR-0045），所以整页自带 `contentWide` 上限：消息列表与输入栏同宽同轴，大屏下
/// 不会出现「气泡收在中间一列、输入框横贯全屏」的错位。
///
/// 本页内还有「历史会话」模式，**页内切换、不新增路由**：本页已经是 push 出来的
/// 整页，再叠「列表页 → 回放页」就成三层栈，输入栏逻辑也会分到两处（ADR-0048）。
/// 历史里每一段**都可续接**——后端只返回本人可见的会话（ADR-0096），「只读回放」
/// 这一态连同它存在的前提一起删掉了。
///
/// 收敛前的旧 `TutorChatScreen` 自带 `TutorNotifier` 与学科/年级/知识点三个控件，
/// 但请求体只发 `message`：控件不生效、DATA 帧被丢弃、会话与悬浮助手互不可见。
/// 这三处已随收敛一并消除。
enum _AssistantMode { chat, history }

class AssistantChatPage extends ConsumerStatefulWidget {
  final bool showBack;

  /// 教师形态：标题与空态引导按教师口径渲染，并开放历史会话入口。
  ///
  /// 教师能出题 / 查任务 / 查学情，学生端只暴露伴学答疑（后端
  /// `AgentRuntime.visible_businesses(role)` 是唯一真相源），所以「只讲学习内容」这句
  /// 边界提示不能照搬给教师。
  final bool isTeacher;

  /// 课件练习透传的课堂上下文（ADR-0072 L2）：非空时本页聚焦到该知识点——
  /// 空态渲染推荐操作目录、内容区顶部展示知识点徽标。课件演示页入口会带此参数；
  /// 全局浮动入口不带（走全局能力目录）。
  final AssistantCoursewareContext? coursewareContext;

  const AssistantChatPage({
    super.key,
    this.showBack = false,
    this.isTeacher = false,
    this.coursewareContext,
  });

  @override
  ConsumerState<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends ConsumerState<AssistantChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  _AssistantMode _mode = _AssistantMode.chat;

  /// 历史列表里正在打开的那一段（行内加载态）。
  String? _openingId;

  /// 是否处于「多选管理」态：是则历史行可勾选、不可点开。
  bool _selecting = false;

  /// 已勾选的会话 id（多选删除的来源）。
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    // 把课件上下文（若有）随每条消息带下去：L2 聚焦只依赖后端 req.courseware，
    // 不必区分首轮 / 续轮——后端每次按 courseware 重新解析知识点上下文。
    ref.read(assistantNotifierProvider.notifier).send(
          text,
          courseware: widget.coursewareContext,
        );
  }

  /// 进入历史列表。每次都重新取列表：会话可能刚在别处被建立 / 续接，缓存会过时。
  void _showHistory() {
    ref.invalidate(conversationHistoryProvider);
    setState(() {
      _mode = _AssistantMode.history;
      _selecting = false;
      _selectedIds.clear();
    });
  }

  /// 进入多选态：清空旧勾选，避免把上一次的选中带进来。
  void _enterSelecting() => setState(() {
        _selecting = true;
        _selectedIds.clear();
      });

  /// 退出多选态：取消勾选、留在历史列表。
  void _exitSelecting() => setState(() {
        _selecting = false;
        _selectedIds.clear();
      });

  /// 勾选 / 取消勾选一段会话。
  void _toggleSelection(AssistantConversation conv) => setState(() {
        if (_selectedIds.contains(conv.id)) {
          _selectedIds.remove(conv.id);
        } else {
          _selectedIds.add(conv.id);
        }
      });

  /// 多选态下「全选 / 取消全选」：已选 == 全部则取消，否则全选。
  ///
  /// 由 [AssistantHistoryView] 的 `_ManageStrip` 调用；列表总条数通过
  /// `conversationHistoryProvider` 取——避免把全量列表再传一遍回调。
  void _toggleSelectAll() {
    final all = ref.read(conversationHistoryProvider).asData?.value;
    if (all == null) return;
    final allIds = all.map((c) => c.id).toSet();
    setState(() {
      if (_selectedIds.length == allIds.length && allIds.isNotEmpty) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  /// 删除勾选的会话：先确认 → 延后删除（5 秒可撤销）→ 到期才真删后端。
  ///
  /// 乐观处理：确认后立刻退出多选并弹「已删除 + 撤销」toast，列表由到期后的
  /// [ref.invalidate] 刷新；窗口内点「撤销」取消定时器，列表原样保持。
  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final ok = await AppDialog.confirm(
      context,
      title: const Text('删除会话'),
      content: Text(
        '确认删除 ${ids.length} 段会话？删除后 5 秒内可撤销。',
      ),
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;

    final count = ids.length;
    final handle = ref.read(assistantRepositoryProvider).scheduleDelete(
      ids,
      onConfirm: () async {
        try {
          await ref.read(assistantRepositoryProvider).deleteConversations(ids);
          if (!mounted) return;
          ref.invalidate(conversationHistoryProvider);
        } catch (e) {
          if (!mounted) return;
          AppToast.error(context, e);
        }
      },
    );

    // 乐观更新：先退出多选（列表待到期刷新），再弹撤销 toast。顺序同原实现——
    // toast 必须挂在稳定 context 上（setState 触发重建会让老 context 失效）。
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _selecting = false;
    });

    AppToast.withAction(
      context,
      '已删除 $count 段会话',
      actionLabel: '撤销',
      onAction: () {
        ref.read(assistantRepositoryProvider).cancelScheduledDelete(handle.id);
        ref.invalidate(conversationHistoryProvider);
      },
    );
  }

  /// 从历史回到对话。只切模式，不动会话本身。
  void _backToChat() => setState(() => _mode = _AssistantMode.chat);

  /// 把「要去哪」交给壳，再关掉自己（若本页是 push 出来的整页）。
  ///
  /// 教师端本页是 `Navigator.push` 的整页，壳在它**下面**——所以不能自己 push，
  /// 得先退回去、由 [HomeScreen] 消费意图切到目标页。学生端本页是壳内页签
  /// （[showBack] = false），原地不动等壳自己切。
  ///
  /// 认不出的 target 什么也不做：后端的 target 是受控枚举，前端猜一个近似落点
  /// 只会把「协议新增了值、前端还没跟上」变成一个莫名其妙的跳转，
  /// 而不是一个能被守卫测出来的失败。
  ///
  /// 引导卡出口与推荐操作（navigate 类）共用同一条分发路径——两者 payload 都是
  /// 既有 [ShellDestination] 受控枚举。
  void _dispatchTarget(String target) {
    final destination = ShellDestination.fromTarget(target);
    if (destination == null) return;
    ref.read(shellNavigationProvider.notifier).request(destination);
    if (widget.showBack) Navigator.of(context).maybePop();
  }

  void _handleCardAction(AssistantCardAction action) =>
      _dispatchTarget(action.target);

  /// 新对话：丢弃当前会话身份与气泡。
  ///
  /// 后端按 `session_id` 续接，不显式断开的话「新对话」只是一句空话。
  void _newConversation() {
    ref.read(assistantNotifierProvider.notifier).reset();
    _ctrl.clear();
    setState(() => _mode = _AssistantMode.chat);
  }

  /// 导出当前对话：本地把消息压成 Markdown，经系统保存面板落盘（file_picker.saveFile），
  /// 复用既有导出落盘通道、不引新依赖。空对话直接提示、不弹面板。
  ///
  /// 落盘由原生保存面板负责（桌面选路径 / 移动端写文档目录），取消保存不提示——
  /// 与 `student_management_screen._downloadTemplate` 同一口径。
  Future<void> _exportConversation() async {
    final current = ref.read(assistantNotifierProvider);
    final messages = switch (current) {
      AssistantActive(:final messages) => messages,
      _ => const <AssistantMessage>[],
    };
    if (messages.isEmpty) {
      AppToast.show(context, '当前没有可导出的对话');
      return;
    }
    final markdown = buildConversationMarkdown(messages);
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: '导出对话记录',
        fileName: 'ai_conversation_${conversationFileNameStamp()}.md',
        bytes: Uint8List.fromList(utf8.encode(markdown)),
      );
      final path = uri?.path;
      if (mounted && path != null) {
        AppToast.show(context, '对话已导出：$path');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  /// 打开一段历史会话 = **恢复续接**（ADR-0096 前分「续接 / 只读」两态）。
  ///
  /// 列表里每一条都是本人的会话，后端归属校验必然通过，续接后消息落回原会话；
  /// 不再需要按归属挑走哪条路径。
  Future<void> _open(AssistantConversation conv) async {
    setState(() => _openingId = conv.id);
    try {
      final detail =
          await ref.read(assistantRepositoryProvider).conversationDetail(conv.id);
      if (!mounted) return;
      ref.read(assistantNotifierProvider.notifier).resume(
            sessionId: detail.conversation.id,
            messages: [
              for (final b in detail.bubbles) AssistantMessage.fromBubble(b),
            ],
          );
      setState(() {
        _mode = _AssistantMode.chat;
        _openingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _openingId = null);
      AppToast.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantNotifierProvider);
    final scheme = AppTheme.colorsOf(context);

    final messages = switch (state) {
      AssistantActive(:final messages) => messages,
      _ => const <AssistantMessage>[],
    };
    final streaming = state is AssistantActive && state.streaming;

    // 流式产出时自动滚到底部（逐帧更新）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mode == _AssistantMode.chat && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            _topBar(),
            Expanded(
              // 宽度上限 + 贴顶：**不用 `Center`**——它连竖向一起居中，消息少时整列
              // 气泡浮在屏幕中间，与本仓「内容贴顶自然布局」的口径冲突（ADR-0045）。
              child: AppContentFrame(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 知识点聚焦徽标（L2）：课件入口带 coursewareContext 时出现，
                    // 与内容同宽同轴（AppTopBar 没有 subtitle 槽，故不走顶栏）。
                    if (widget.coursewareContext != null) _knowledgePointBadge(),
                    Expanded(
                      child: switch (_mode) {
                          _AssistantMode.chat => messages.isEmpty
                              ? _buildEmptyState()
                              : AssistantMessageList(
                                  messages: messages,
                                  controller: _scroll,
                                  onCardAction: _handleCardAction,
                                  onPrompt: (payload) => ref
                                      .read(assistantNotifierProvider.notifier)
                                      .send(payload, courseware: widget.coursewareContext),
                                  onNavigate: _dispatchTarget,
                                ),
                          _AssistantMode.history => AssistantHistoryView(
                              onOpen: _open,
                              openingId: _openingId,
                              selecting: _selecting,
                              selectedIds: _selectedIds,
                              onToggleSelection: _toggleSelection,
                              onEnterSelecting: _enterSelecting,
                              onToggleSelectAll: _toggleSelectAll,
                            ),
                        },
                    ),
                  ],
                ),
              ),
            ),
            if (_mode == _AssistantMode.chat) ...[
              _hairline(scheme),
              AssistantInputBar(controller: _ctrl, sending: streaming, onSend: _send),
            ],
          ],
        ),
      ),
    );
  }

  /// 顶栏即模式切换器：对话态给「新对话 / 历史 / 导出」三连，历史态给「新对话」。
  ///
  /// 对话态把常用动作都收进顶栏：最左「新对话」（plus）开一段空白会话，紧挨其右
  /// 「历史」翻看旧会话，最右「导出」落盘——三者各占一个图标槽位。
  /// 历史态的 trailing 换成「新对话」是有意的——去翻历史的人，下一步常常就是想开一段新的。
  Widget _topBar() {
    switch (_mode) {
      case _AssistantMode.chat:
        return AppTopBar(
          title: widget.isTeacher ? 'AI 学习助手' : '问 AI 老师',
          showBack: widget.showBack,
          // 历史入口**双端都有**（ADR-0096）：后端按调用者身份返回本人可见的会话，
          // 学生看到的就是自己问过的。ADR-0048 曾把它定为教师专属（「有意的不对称」），
          // 那条理由随归属收敛不再成立。
          // 历史入口与导出并列：三者都是对话态的常用动作，各占一个图标槽位。
          // trailing 已放开固定 40 宽（app_top_bar.dart），多个图标并排不会裁切。
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconAction(
                icon: LucideIcons.plus,
                iconSize: 20,
                semanticLabel: '新对话',
                onPressed: _newConversation,
              ),
              AppIconAction(
                icon: LucideIcons.history,
                iconSize: 20,
                semanticLabel: '历史会话',
                onPressed: _showHistory,
              ),
              AppIconAction(
                icon: LucideIcons.download,
                iconSize: 20,
                semanticLabel: '导出对话',
                onPressed: _exportConversation,
              ),
            ],
          ),
        );
      case _AssistantMode.history:
        return AppTopBar(
          // 多选态下 title 始终是「选择会话」——计数由列表顶部的 _ManageStrip 显示，
          // 避免同一数字在两处出现、改起来不同步（arrange：单一真相源）。
          title: _selecting ? '选择会话' : '历史会话',
          showBack: true,
          // 多选态下返回 = 退出多选（留在列表）；非多选态 = 回对话。
          onBack: _selecting ? _exitSelecting : _backToChat,
          trailing: _selecting
              ? AppIconAction(
                  icon: LucideIcons.trash2,
                  iconSize: 20,
                  semanticLabel: '删除选中会话',
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                )
              : AppIconAction(
                  icon: LucideIcons.plus,
                  iconSize: 20,
                  semanticLabel: '新对话',
                  onPressed: _newConversation,
                ),
        );
    }
  }

  /// 结构分隔线：发丝档（与顶栏底边、侧栏右缘同一档，ADR-0044）。
  Widget _hairline(AppColors scheme) => Container(
        height: AppElevation.borderWidthHairline,
        color: scheme.outline,
      );

  /// 空态：引导卡（按角色分叉）+ 推荐操作目录（L1 chips）。
  ///
  /// 目录由 [AssistantSuggestedActions] 从后端静态目录拉取，目录内容随
  /// [widget.coursewareContext] 是否聚焦知识点而变化（全局能力 vs 知识点聚焦）。
  Widget _buildEmptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WelcomeHint(isTeacher: widget.isTeacher),
        AssistantSuggestedActions(
          coursewareContext: widget.coursewareContext,
          onPrompt: (payload) => ref
              .read(assistantNotifierProvider.notifier)
              .send(payload, courseware: widget.coursewareContext),
          onNavigate: _dispatchTarget,
        ),
      ],
    );
  }

  /// 知识点聚焦徽标（L2）：课件入口带 [widget.coursewareContext] 时出现，
  /// 展示「知识点名 · 学科 · 年级 · 学期」，让使用者一眼知道这段对话聚焦在哪。
  ///
  /// 走 surfaceSunken 底 + hairline 边，与 `_PresentStage` 的提问卡同一视觉档；
  /// 放在内容区顶部、与消息 / 输入框同宽同轴（AppTopBar 无 subtitle 槽，故不放顶栏）。
  Widget _knowledgePointBadge() {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final ctx = widget.coursewareContext!;
    final meta = [
      if (ctx.subject != null && ctx.subject!.isNotEmpty) ctx.subject!,
      if (ctx.grade != null) '${ctx.grade}年级',
      if (ctx.semester != null && ctx.semester!.isNotEmpty) ctx.semester!,
    ].join(' · ');
    final name = ctx.knowledgePoint ?? '知识点';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: scheme.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.target, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                meta.isEmpty ? name : '$name · $meta',
                style: text.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态引导：告诉使用者这个入口能问什么、边界在哪。
///
/// 文案按角色分叉（见 [AssistantChatPage.isTeacher]）：学生端强调「只讲学习内容」的
/// 边界，教师端强调「能出题 / 查任务 / 看学情」的能力。骨架走 [AssistantHintCard]，
/// 与历史空态是同一个东西。
///
/// ⚠️ 教师端那句曾是「一句话就能发布任务」——**它做不到**：助手是只读的（写操作
/// 一律引导到对应页面）。空态是承诺最密集的位置，写一句做不到的话，用户只会在
/// 试过之后觉得「这助手坏了」。空态只说**真能做的**，「发布任务」由引导卡给出口。
class _WelcomeHint extends StatelessWidget {
  final bool isTeacher;

  const _WelcomeHint({required this.isTeacher});

  @override
  Widget build(BuildContext context) => AssistantHintCard(
        icon: LucideIcons.sparkles,
        title: isTeacher ? '可以出题、查学情、看错题' : '有问题就问 AI 老师吧',
        body: isTeacher ? '布置与派发任务请到「任务」页，点右上角「发布任务」' : '只讲学习内容，其他问题不回答哦',
      );
}
