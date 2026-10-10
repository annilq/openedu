/// 未配置交互讲解模板时的**开发者指引**（不是教师配置向导）。
///
/// 交互讲解模板是开发者实现的场景组件，不是教师在前端手配的——编辑器只能编辑已
/// 存在的 reflection（轴对称）类模板，无法凭空造出「平移」等新类型。所以点开一个
/// 还没有模板的知识点时，不渲染 reflection 表单，而是给开发者看：怎样以现有
/// reflection 组件为范本新建一个 kind 并接入系统。
///
/// 单独成文件：这段养护指引约 50 行，放在编辑器里会把它顶过 ADR-0058 的 400 行
/// 上限。搬出来的同时也在说明一件事——「怎样新增 kind」是一份**独立文档**，不是
/// 编辑器的一个分支状态。
///
/// 卡片里点名的文件均为真实路径（前后端 kind 双登记约束见 ADR-0061 §O）。
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../shared/theme/app_theme.dart';

class SceneDeveloperGuide extends StatelessWidget {
  const SceneDeveloperGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: app.secondary.withValues(alpha: 0.08),
        border: Border.all(color: app.secondary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build, size: 16, color: app.secondary),
              const SizedBox(width: AppSpacing.xs),
              Text('尚未配置交互讲解模板（开发者任务）', style: text.labelMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '该知识点还没有可渲染的交互讲解模板。交互讲解模板是开发者实现的场景组件，'
            '不是家长在前端手动配置的——本弹窗只能编辑已存在的 reflection（轴对称）类'
            '模板，无法凭空造出「平移」等新类型。\n\n'
            '要为本知识点新增交互讲解，开发者以现有 reflection 组件为范本新建一个 kind：\n\n'
            '① 登记新 kind（前后端双登记）：前端 '
            'lib/shared/widgets/scene_interpreter/scene_interpreter.dart 的 SceneKind '
            '枚举加一项（如 translation）、build() 的 switch 增加对应 case 返回新渲染器、'
            'SceneKindX.fromName 增加映射；后端 scene_fusion.py / scene_extract.py 保持 '
            'kind 词汇表一致。内置场景登记进 '
            'backend/app/features/materials/scene_templates.py 的 SCENE_LIBRARY（ADR-0073）。\n\n'
            '② 实现渲染器（参照 reflection_scene.dart + reflection_scene_data.dart）：'
            '前者是「渲染/交互」层（画布 + 拖拽 + 播放），后者是「数据与几何」层（解析 '
            'SceneSpec、顶点、绘制）。平移组件复用「给一组顶点画多边形」的骨架，把'
            '「对折」换成「沿向量平移 + 逐顶点运动」。交互参数与引导文案按 kind 收进 '
            'lib/shared/widgets/scene_interpreter/scene_shells.dart 的 kSceneShells '
            '（后端 scene_templates.py 的 SCENE_LIBRARY 同构镜像）。\n\n'
            '③ 几何不进代码：图形存在 figure_library 表（内置 11 条由 '
            'backend/app/features/materials/scene_figures.py 的 BUILTIN_FIGURE_SEED '
            '播种，用户行由图形画板保存）；图库只在画板 / 画廊这类创作 UI 打开时按需 '
            'GET /api/v1/materials/scene-library/figures。**运行时渲染零图库依赖**：'
            'SceneSpec 自带几何，别在渲染路径里回查图库。\n\n'
            '④ 产出 SceneSpec 并接入知识点：字段只有三个 —— kind、points（[[x,y]…]，'
            '归一化 0..1、y 向下）、edges（[[i,j]…] 顶点索引对，空则按顺序闭合）。'
            '轴初值 / controls / 引导文案 / title **都不是 spec 字段**（ADR-0083 决策 '
            '5/6：归 kind 外壳）。多选项用 optionGroup 派生多份实例，每条内联自己的 '
            'points + edges。模板写入 KnowledgePoint.scenes（List[SceneSpec]），经 '
            'PATCH /api/v1/materials/knowledge-points/{kp_id}/scenes'
            '（update_knowledge_point_scenes）落库，scene_fusion.py 按题目学期解析。\n\n'
            '完成后本弹窗会按该知识点的真实 kind 渲染专属交互讲解，不再回退到轴对称模板。',
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
