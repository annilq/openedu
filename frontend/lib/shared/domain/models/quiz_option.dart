// 选择题选项模型（ADR-0089-04）：选项可内嵌平面图形。
//
// 后端出题侧（tasks/question subagent）与答疑侧现在都把选项表达为
// `list[{text, figure?}]`——`text` 恒存（判题 + 无障碍，ADR-0061 §T），`figure`
// 是内联几何（归一化顶点 + 连接关系，渲染只吃这个、零图库依赖、离线）。
//
// **

// **tolerant parse**：老数据 / 旧端点仍可能下发纯字符串选项（`"A. 房子"`），
// 必须零回归地落进「带空图形的对象」。新形（`{text, figure}`）才解析几何。
//
// 几何解析复用 [SceneSpec.parseFigure]（与场景规格同一把锁，不另写一套顶点解析）。

import '../figures.dart';
import '../scene_spec.dart';

/// 一道选择题选项：文案 + 可选图形。
class QuizOption {
  /// 选项文案（恒存，判题比对与渲染都吃它；字母前缀由 [cleanOptionText] 剥离）。
  final String text;

  /// 选项内嵌的平面图形；null = 纯文字选项（不渲染图形区）。
  final FigureShape? figure;

  const QuizOption({required this.text, this.figure});

  /// 单个选项 tolerant 解析：String → 纯文字选项；Map → 取 text + 可选 figure。
  static QuizOption parse(Object? raw) {
    if (raw is Map) {
      return QuizOption(
        text: (raw['text'] as String?) ?? '',
        figure: SceneSpec.parseFigure(raw['figure']),
      );
    }
    return QuizOption(text: raw?.toString() ?? '', figure: null);
  }

  /// 选项列表 tolerant 解析：null / 非 List → null；否则逐条 [parse]。
  static List<QuizOption>? parseList(Object? raw) {
    if (raw is! List) return null;
    return [for (final e in raw) parse(e)];
  }

  /// 回写后端新形：纯文字选项 → `{text}`；带图形 → `{text, figure}`。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        if (figure != null) 'figure': SceneSpec.figureToJson(figure!),
      };
}
