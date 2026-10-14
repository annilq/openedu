# 07: 侧栏改名与分组

**What to build:** 教师侧栏不再有「资料库 / 素材库」这对近义命名——教师一眼能分清哪个是教学文档与知识点备课、哪个是自传图片素材。同时侧栏按「教学 / 备课资源」两组呈现，组间有分隔与组标题，不再是 11 个等权重平级项。

**Blocked by:** 01（标题与图标的单一映射表）

**Status:** done（2026-10-14 合入 integration/nav-ia-review，merge 5ee599c；3 逻辑提交 790fe8f / 041ec86 / 72223ea）

## 验收

- [x] 原「资料库」改名为能表达「教学文档 + 知识点备课」的名字 → **备课资料**（page_labels + 8 处消费者同步）
- [x] 原「素材库」改名为能表达「自传图片素材」的名字 → **图片素材**
- [x] 两个新名字在教师视角下不再近义（设计层面：资料库=教学文档+知识点备课 ADR-0055，素材库=自传图片 ADR-0077；二选一人工走查为手动步骤，未纳入自动化）
- [x] 侧栏按「教学 / 备课资源 / 系统」三组呈现，组间有分隔与组标题
      （注：原 ticket 写「两组」，实现增「系统」组暂存 模型管理 / 运行轨迹，ticket 08 将把系统项收进「我的」后该组消失）
- [x] 侧栏收起态（仅图标）下组标题退化为间距，图标仍可区分（AppSidebarGroupTitle 收起态 SizedBox 间距）
- [x] 所有改名同步到页面内文案与空态引导——同一个概念不出现两套叫法（material_library_view / material_knowledge_manage_view / scene_library_associate_dialog / courseware_create_sheet / asset_library_screen / asset_library_picker / section_material_picker / section_media_gallery）
- [x] 组标题与分隔走既有排版令牌与结构边档，不新增裸数字
- [x] widget 测试：两组与组标题渲染正确；收起态不渲染组标题（page_labels_test / adaptive_shell 系列 / device_size_fit / student_profile_slot）

## 实现说明

- 把 `AdaptiveNavDestination` 从 `adaptive_shell.dart` 抽到中性的 `nav_section.dart`，新增 `SidebarSection`
  分组结构 + `AppSidebarGroupTitle`；壳三形态（侧栏/底栏/抽屉）共用同一份分组定义。抽离后
  `adaptive_shell.dart` 531→525 行，过 ADR-0058 文件规模棘轮（file_size_guard 通过）。
- 测试脆弱性修复：默认 800×600 下侧栏是 lazy ListView，分组后「运行轨迹」落「系统」组末位（第 14 行）
  渲染不到，`find.text('运行轨迹')` 落空；在 `teacher_nav_single_source_test` / `ai_run_trace_page_test`
  的 `_pumpTeacherHome` 泵前 `setSurfaceSize(1000,900)` + `addTearDown` 还原。
- 未做：课件创建入口错位（明确不做项，另开）；人工二选一走查（手动）。

## 纪律

- **只改信息架构与文案**，不改任何页面的内容、不改后端命名、不动数据库字段。
- 分组顺序按教学动线（先教什么、再备什么），不按字母或实现顺序。
- 课件的**创建入口错位**不在本票修（它在备课资料页里），本票只保证两条路径的叫法一致。
