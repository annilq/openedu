import 'package:cupertino_ui/cupertino_ui.dart';
// LucideIcons 由 shadcn_ui 再导出。
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';

/// 兴趣分类词表（WF-1 定稿）：15 个一级 → 可选二级叶子。
/// 取值语义见 wayfinder/tickets/01-兴趣分类词表.md。
const Map<String, List<String>> kInterestTaxonomy = {
  '动物': ['恐龙', '猫狗宠物', '海洋生物', '昆虫', '鸟类', '猛兽'],
  '自然': ['植物', '天气', '山川河流', '星空'],
  '太空': ['行星', '火箭宇航员', '外星', '星系'],
  '科学': ['实验', '物理现象', '机器人', '化学'],
  '运动': ['足球', '篮球', '游泳', '跳绳', '跑步', '体操'],
  '艺术': ['绘画', '手工', '雕塑', '舞蹈'],
  '音乐': ['乐器', '儿歌', '流行歌', '节奏'],
  '故事阅读': ['童话', '神话', '冒险小说', '漫画'],
  '动画影视': ['国产动画', '迪士尼皮克斯', '超级英雄', '怪兽'],
  '历史文化': ['古代中国', '古代世界', '传统节日', '名人'],
  '美食': ['烘焙', '水果', '各国料理', '甜点'],
  '机械交通': ['汽车', '火车', '飞机', '工程车'],
  '编程科技': ['积木编程', '游戏设计', 'AI'],
  '角色扮演': ['公主', '骑士', '医生护士', '超人'],
  '玩具游戏': ['乐高', '拼图', '桌游', '盲盒'],
};

/// 兴趣采集组件（WF-5）：两级分类多选 + 「其他爱好」自由文本（≤50 字）。
///
/// 全空时通过 [onChanged] 回传 `null`，否则回传 [InterestsModel]。
/// 支持 [initial] 回填（编辑娃娃资料场景）。
class InterestPicker extends StatefulWidget {
  final InterestsModel? initial;
  final ValueChanged<InterestsModel?> onChanged;

  const InterestPicker({
    super.key,
    this.initial,
    required this.onChanged,
  });

  @override
  State<InterestPicker> createState() => _InterestPickerState();
}

class _InterestPickerState extends State<InterestPicker> {
  final Set<String> _selected = {};
  final TextEditingController _freeCtrl = TextEditingController();
  static const int _freeMax = 50;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _selected.addAll(init.categories);
      _freeCtrl.text = init.freeText ?? '';
    }
    _freeCtrl.addListener(_emit);
  }

  @override
  void dispose() {
    _freeCtrl.removeListener(_emit);
    _freeCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    // 自由文本限长 50 字：超出截断并回正光标。
    final raw = _freeCtrl.text;
    if (raw.length > _freeMax) {
      final truncated = raw.substring(0, _freeMax);
      _freeCtrl.value = _freeCtrl.value.copyWith(
        text: truncated,
        selection: TextSelection.collapsed(offset: truncated.length),
      );
    }
    final free = _freeCtrl.text.trim();
    final model = InterestsModel(
      categories: _selected.toList(),
      freeText: free.isEmpty ? null : free,
    );
    widget.onChanged(model.isEmpty ? null : model);
  }

  void _toggle(String leaf) {
    setState(() {
      if (_selected.contains(leaf)) {
        _selected.remove(leaf);
      } else {
        _selected.add(leaf);
      }
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('兴趣标签（可选）',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '选择娃娃感兴趣的主题，AI 出题时会融入这些情境，让练习更有趣。',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        ...kInterestTaxonomy.entries.map((e) => _CategoryBlock(
              category: e.key,
              leaves: e.value,
              selected: _selected,
              onToggle: _toggle,
            )),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: '其他爱好（可选，≤$_freeMax 字）',
          controller: _freeCtrl,
          hintText: '如：养蚕、乐高城市',
          prefixIcon: LucideIcons.heart,
          onChanged: (_) {}, // 截断与回传由 _freeCtrl 监听统一处理
        ),
        if (_freeCtrl.text.length >= _freeMax)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('已达 $_freeMax 字上限',
                style: text.labelSmall?.copyWith(color: app.error)),
          ),
      ],
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  final String category;
  final List<String> leaves;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _CategoryBlock({
    required this.category,
    required this.leaves,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category, style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: leaves
                .map((leaf) => _LeafToggle(
                      label: leaf,
                      selected: selected.contains(leaf),
                      onTap: () => onToggle(leaf),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LeafToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LeafToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 1.5 : 0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(LucideIcons.check,
                    size: 16, color: scheme.onPrimaryContainer),
              ),
            Text(label,
                style: text.labelMedium?.copyWith(
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}
