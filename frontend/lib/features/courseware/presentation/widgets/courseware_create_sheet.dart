import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../home/domain/repositories/material_repository.dart';
import '../../domain/models/courseware.dart';
import '../../domain/repositories/courseware_repository.dart';
import '../../providers/courseware_provider.dart';

/// 新增课件表单（courseware-round-3 T01）：选知识点 + 标题 + 教学目标。
///
/// 提交时调 [CoursewareRepository.createCourseware]（[draft]=false）建**零环节空壳**
/// （不触发 AI），返回建好的 [CoursewareModel]，由调用方直接打开编辑器。知识点来源
/// 走后端 `GET /materials/knowledge-points/all` 一次拿到跨范围全集，不要求先选范围。
///
/// 返回 null = 用户取消。
Future<CoursewareModel?> showCoursewareCreateSheet(
  BuildContext context,
  WidgetRef ref,
) =>
    showDialog<CoursewareModel>(
      context: context,
      builder: (_) => const _CoursewareCreateSheet(),
    );

class _CoursewareCreateSheet extends ConsumerStatefulWidget {
  const _CoursewareCreateSheet();

  @override
  ConsumerState<_CoursewareCreateSheet> createState() =>
      _CoursewareCreateSheetState();
}

class _CoursewareCreateSheetState extends ConsumerState<_CoursewareCreateSheet> {
  List<KnowledgePointOption> _kps = const [];
  bool _loading = true;
  String? _loadError;

  KnowledgePointOption? _selectedKp;
  final _titleCtl = TextEditingController();
  final _objectiveCtl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadKps);
  }

  Future<void> _loadKps() async {
    setState(() => _loading = true);
    try {
      final kps =
          await ref.read(coursewareRepositoryProvider).listKnowledgePoints();
      if (!mounted) return;
      setState(() {
        _kps = kps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _objectiveCtl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final kp = _selectedKp;
    if (kp == null || kp.id == null) {
      AppToast.show(context, '请先选择一个知识点');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final title = _titleCtl.text.trim();
      final objective = _objectiveCtl.text.trim();
      final created = await ref.read(coursewareRepositoryProvider).createCourseware(
            knowledgePointId: kp.id!,
            title: title.isEmpty ? null : title,
            objective: objective.isEmpty ? null : objective,
            draft: false,
          );
      if (!mounted) return;
      // 直接把建好的空壳交回调用方（避免编辑器再按 KP 查一遭，也避免同 KP 多课件时取到旧的那份）。
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '创建课件失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final disabled = _busy || _loading || _kps.isEmpty;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: (MediaQuery.of(context).size.height - 96).clamp(420, 760),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('新增课件', style: text.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '选一个知识点建一份空课件，随后手动添加环节或用「AI 补充讲解」。',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: _loading
                    ? const Center(child: AppLoading())
                    : _loadError != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('知识点加载失败：$_loadError',
                                    style: text.bodySmall
                                        ?.copyWith(color: app.error)),
                                AppTextAction(label: '重试', onPressed: _loadKps),
                              ],
                            ),
                          )
                        : _kps.isEmpty
                            ? Center(
                                child: Text(
                                  '还没有任何知识点。先到「资料库」上传教材并完成提取，'
                                  '知识点会自动出现。',
                                  style: text.bodySmall
                                      ?.copyWith(color: app.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppPickerField<KnowledgePointOption>(
                                      label: '知识点',
                                      values: _kps,
                                      labels: [
                                        for (final kp in _kps)
                                          '${kp.name}${kp.semester.isNotEmpty ? '（${kp.semester}）' : ''}',
                                      ],
                                      value: _selectedKp,
                                      placeholder: '请选择知识点',
                                      onChanged: (v) =>
                                          setState(() => _selectedKp = v),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    AppTextField(
                                      label: '课件标题',
                                      controller: _titleCtl,
                                      hintText: '留空则使用知识点名',
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    AppTextField(
                                      label: '教学目标 / 备课依据（选填）',
                                      controller: _objectiveCtl,
                                      hintText: '「AI 补充讲解」时会参考这里',
                                    ),
                                  ],
                                ),
                              ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppTextAction(
                    label: '取消',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppPrimaryButton(
                    label: '创建空课件',
                    fullWidth: false,
                    loading: _busy,
                    onPressed: disabled ? null : _create,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
