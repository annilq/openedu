part of 'class_management_screen.dart';

/// 班级表单（新建 / 重命名共用）：名称 + 年级 1–9 选择器 + 确定 / 取消。
class _ClassForm extends StatefulWidget {
  final String initialName;
  final int initialGrade;
  final FutureOr<void> Function(String name, int grade) onSubmit;
  final VoidCallback onCancel;

  const _ClassForm({
    required this.initialName,
    required this.initialGrade,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<_ClassForm> createState() => _ClassFormState();
}

class _ClassFormState extends State<_ClassForm> {
  final _name = TextEditingController();
  late int _grade = widget.initialGrade;
  bool _submitting = false;

  static final List<int> _grades = List<int>.generate(9, (i) => i + 1);

  @override
  void initState() {
    super.initState();
    _name.text = widget.initialName;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppToast.error(context, Exception('请填写班级名称'));
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(name, _grade);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: scheme.outline, width: AppElevation.borderWidth),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: '班级名称',
            hintText: '如 三(1)班 / 1级2班',
            controller: _name,
            prefixIcon: LucideIcons.school,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppPickerField<int>(
            label: '年级',
            values: _grades,
            labels: _grades.map((g) => '$g 年级').toList(),
            value: _grade,
            onChanged: (g) => setState(() => _grade = g),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppTextAction(label: '取消', onPressed: widget.onCancel),
              const Spacer(),
              ShadButton(
                onPressed: _submitting ? null : _submit,
                child: Text('确定',
                  style: text.labelMedium?.copyWith(color: scheme.onPrimary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 重命名底部抽屉表单（页内浮层，不依赖 Material Dialog）。
class _ClassFormSheet extends StatelessWidget {
  final ClassModel classModel;
  final VoidCallback onClose;
  final FutureOr<void> Function(String name, int grade) onSubmit;

  const _ClassFormSheet({
    required this.classModel,
    required this.onClose,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: AppFocusableAction(
            onTap: onClose,
            semanticLabel: '关闭',
            child: Container(color: scheme.scrim),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: scheme.outline, width: AppElevation.borderWidth),
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text('重命名班级', style: text.titleMedium),
                ),
                Container(height: 1, color: scheme.outline),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: _ClassForm(
                      initialName: classModel.name,
                      initialGrade: classModel.grade,
                      onSubmit: onSubmit,
                      onCancel: onClose,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
