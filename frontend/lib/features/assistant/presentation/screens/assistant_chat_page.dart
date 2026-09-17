import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_content_frame.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../domain/conversation.dart';
import '../../providers/assistant_provider.dart';
import '../provider/assistant_notifier.dart';
import '../provider/conversation_history_provider.dart';
import '../widgets/assistant_hint_card.dart';
import '../widgets/assistant_history_view.dart';
import '../widgets/assistant_message_list.dart';

/// AI 单入口整页形态（ADR-0036 / ADR-0047）：**双端唯一的助手页面**。
///
/// - 娃娃端：导航空壳的「问 AI 老师」页签（[showBack] = false）；
/// - 家长端：浮动按钮 push 出来的整页（[showBack] = true，[isParent] = true）。
///
/// 两端共用同一 [assistantNotifierProvider] 与同一 [AssistantMessageList]——同一个 AI
/// 能力、同一份会话、同一套渲染，只用 [isParent] 切换标题与空态引导的口径。
///
/// 本页可能经 `Navigator.push` 打开（家长端），此时它**不在导航壳的宽度兜底范围内**
/// （ADR-0045），所以整页自带 `contentWide` 上限：消息列表与输入栏同宽同轴，大屏下
/// 不会出现「气泡收在中间一列、输入框横贯全屏」的错位。
///
/// 家长端在本页内还有「历史会话」与「只读回放」两种模式，**页内切换、不新增路由**：
/// 本页已经是 push 出来的整页，再叠「列表页 → 回放页」就成三层栈，输入栏逻辑也会
/// 分到两处（ADR-0048）。
///
/// 收敛前的旧 `TutorChatScreen` 自带 `TutorNotifier` 与学科/年级/知识点三个控件，
/// 但请求体只发 `message`：控件不生效、DATA 帧被丢弃、会话与悬浮助手互不可见。
/// 这三处已随收敛一并消除。
enum _AssistantMode { chat, history, reading }

class AssistantChatPage extends ConsumerStatefulWidget {
  final bool showBack;

  /// 家长形态：标题与空态引导按家长口径渲染，并开放历史会话入口。
  ///
  /// 家长能出题 / 查任务 / 查学情，娃娃端只暴露伴学答疑（后端
  /// `AgentRuntime.visible_businesses(role)` 是唯一真相源），所以「只讲学习内容」这句
  /// 边界提示不能照搬给家长。
  final bool isParent;

  const AssistantChatPage({
    super.key,
    this.showBack = false,
    this.isParent = false,
  });

  @override
  ConsumerState<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends ConsumerState<AssistantChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  /// 只读回放用自己的滚动控制器：复用 [_scroll] 会把上一模式的偏移带进来，
  /// 打开一段旧对话应该是从头看，而不是接着聊天列表的位置。
  final _replayScroll = ScrollController();

  _AssistantMode _mode = _AssistantMode.chat;

  /// 历史列表里正在打开的那一段（行内加载态）。
  String? _openingId;

  /// 只读回放的内容（孩子的会话）。家长自己的会话走 [_resumeToChat]，不进这里。
  AssistantConversationDetail? _replay;

  /// 是否处于「多选管理」态：是则历史行可勾选、不可点开。
  bool _selecting = false;

  /// 已勾选的会话 id（多选删除的来源）。
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _replayScroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    ref.read(assistantNotifierProvider.notifier).send(text);
  }

  /// 进入历史列表。每次都重新取列表：会话可能刚在别处被建立 / 续接，缓存会过时。
  void _showHistory() {
    ref.invalidate(conversationHistoryProvider);
    setState(() {
      _mode = _AssistantMode.history;
      _replay = null;
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

  /// 从历史 / 只读回到对话。只切模式，不动会话本身。
  void _backToChat() => setState(() {
        _mode = _AssistantMode.chat;
        _replay = null;
      });

  void _backToHistory() => _showHistory();

  /// 新对话：丢弃当前会话身份与气泡。
  ///
  /// 后端按 `session_id` 续接，不显式断开的话「新对话」只是一句空话。
  void _newConversation() {
    ref.read(assistantNotifierProvider.notifier).reset();
    _ctrl.clear();
    setState(() {
      _mode = _AssistantMode.chat;
      _replay = null;
    });
  }

  /// 打开一段历史会话：我的 → 恢复续接；孩子的 → 只读回放。
  ///
  /// 分叉的依据是条目本身的归属（[AssistantConversation.isMine]），不是模式状态：
  /// 孩子的会话**不能**续接（家长发请求时 child_id 恒为 None，过不了后端归属校验，
  /// 后端会另建一段而屏幕上像续上了）。
  Future<void> _open(AssistantConversation conv) async {
    setState(() => _openingId = conv.id);
    try {
      final detail =
          await ref.read(assistantRepositoryProvider).conversationDetail(conv.id);
      if (!mounted) return;
      if (conv.isMine) {
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
      } else {
        setState(() {
          _mode = _AssistantMode.reading;
          _replay = detail;
          _openingId = null;
        });
      }
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

    // 流式产出时自动滚到底部（逐帧更新）。只读回放不参与：它用另一个控制器。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mode == _AssistantMode.chat && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });

    final replay = _replay;

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
                child: switch (_mode) {
                    _AssistantMode.chat => messages.isEmpty
                        ? _WelcomeHint(isParent: widget.isParent)
                        : AssistantMessageList(
                            messages: messages,
                            controller: _scroll,
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
                    _AssistantMode.reading => replay == null
                        ? const SizedBox.shrink()
                        : AssistantMessageList(
                            messages: [
                              for (final b in replay.bubbles)
                                AssistantMessage.fromBubble(b),
                            ],
                            controller: _replayScroll,
                          ),
                  },
              ),
            ),
            if (_mode == _AssistantMode.chat) ...[
              _hairline(scheme),
              _InputBar(controller: _ctrl, sending: streaming, onSend: _send),
            ],
            if (_mode == _AssistantMode.reading) ...[
              _hairline(scheme),
              _ReadOnlyNotice(childName: replay?.conversation.childName),
            ],
          ],
        ),
      ),
    );
  }

  /// 顶栏即模式切换器：对话态给「历史」，历史态给「新对话」，回放态给「回列表」。
  ///
  /// 两个动作各占一个 40 宽槽位，不额外挤第二个图标：历史态的 trailing 换成「新对话」
  /// 是有意的——去翻历史的人，下一步常常就是想开一段新的。
  Widget _topBar() {
    switch (_mode) {
      case _AssistantMode.chat:
        return AppTopBar(
          title: widget.isParent ? 'AI 学习助手' : '问 AI 老师',
          showBack: widget.showBack,
          // 历史入口**只给家长**：后端没有 child-scoped 的会话列表路由，且孩子看到
          // 自己「被拦过」的记录是负面强化（ADR-0048 记录了这个有意的不对称）。
          trailing: widget.isParent
              ? AppIconAction(
                  icon: LucideIcons.history,
                  iconSize: 20,
                  semanticLabel: '历史会话',
                  onPressed: _showHistory,
                )
              : null,
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
                  icon: LucideIcons.squarePen,
                  iconSize: 20,
                  semanticLabel: '新对话',
                  onPressed: _newConversation,
                ),
        );
      case _AssistantMode.reading:
        final name = _replay?.conversation.childName;
        return AppTopBar(
          title: name == null ? '会话回放' : '$name的对话',
          showBack: true,
          onBack: _backToHistory,
        );
    }
  }

  /// 结构分隔线：发丝档（与顶栏底边、侧栏右缘同一档，ADR-0044）。
  Widget _hairline(AppColors scheme) => Container(
        height: AppElevation.borderWidthHairline,
        color: scheme.outline,
      );
}

/// 空态引导：告诉使用者这个入口能问什么、边界在哪。
///
/// 文案按角色分叉（见 [AssistantChatPage.isParent]）：娃娃端强调「只讲学习内容」的
/// 边界，家长端强调「能出题 / 查任务 / 看学情」的能力。骨架走 [AssistantHintCard]，
/// 与历史空态是同一个东西。
class _WelcomeHint extends StatelessWidget {
  final bool isParent;

  const _WelcomeHint({required this.isParent});

  @override
  Widget build(BuildContext context) => AssistantHintCard(
        icon: LucideIcons.sparkles,
        title: isParent ? '一句话就能布置任务' : '有问题就问 AI 老师吧',
        body: isParent ? '可以出题、查任务、看错题与掌握度' : '只讲学习内容，其他问题不回答哦',
      );
}

/// 只读回放的底栏：孩子的会话不能续接，输入栏换成一句说明。
///
/// **替换而不是隐藏**：直接去掉底栏会让人以为界面坏了，而这里必须说清**为什么**
/// 不能输入——否则用户会反复点空白处，以为是自己没点对。
class _ReadOnlyNotice extends StatelessWidget {
  final String? childName;

  const _ReadOnlyNotice({this.childName});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return SafeArea(
      top: false,
      // 与消息列表、输入栏同宽同轴（本页可能 push 在壳外）。
      child: AppContentFrame(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl),
          child: Row(
            children: [
              Icon(LucideIcons.lock,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '这是${childName ?? '孩子'}的对话，只能查看，不能继续提问',
                  style: text.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部输入栏：多行问题输入 + 发送。
///
/// 旧的「相关知识点（选填）」输入框已删除——它对应的字段没进请求体，是死 UI。
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return SafeArea(
      top: false,
      // 与消息列表同宽同轴：本页可能 push 在壳外（家长端），不套上限的话大屏下
      // 输入框会横贯全屏、气泡却收在中间一列。
      child: AppContentFrame(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ShadInput(
                  controller: controller,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 4,
                  style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                  placeholder: Text('输入你的学习问题…',
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  cursorColor: scheme.primary,
                  // 单行高度取「主行动档」，与右侧发送按钮同档：两者是同一组
                  // 控件，必须同高。此前输入框靠 `vertical: 14` 撑到 51px、按钮
                  // 硬编码 52、再用 `Padding(bottom: 2)` 手工找平——三个魔数互相
                  // 追着补。现在高度由同一令牌决定，竖向 padding 只负责多行时的
                  // 呼吸感（8+单行+8 = 37 < 48，单行仍是精确的 48，多行按内容增高）。
                  constraints: BoxConstraints(
                      minHeight: AppControl.heightLgOf(context)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(LucideIcons.pencil,
                        color: scheme.onSurfaceVariant, size: 20),
                  ),
                  decoration: ShadDecoration(
                    disableSecondaryBorder: true,
                    color: scheme.surfaceContainerLow,
                    border: ShadBorder.all(
                      color: scheme.outline,
                      width: 1,
                      radius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AppPrimaryButton(
                label: '发送',
                icon: LucideIcons.send,
                loadingLabel: '思考中',
                loading: sending,
                onPressed: onSend,
                height: AppControl.heightLgOf(context),
                fullWidth: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
