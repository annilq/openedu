# ADR-0077 课件素材库：纯教师上传 + 独立入口 + 多选 picker

- 状态：提案（待评审）
- 日期：2026-10-08
- 关联：ADR-0067（课件编辑器 · 环节内容块统一化）、ADR-0076（课件多图演示 / 只读画廊）、ADR-0055（资料库，教师上传 + 向量化）、ADR-0059（单源导航）、ADR-0051（空态）、ADR-0044/0046（视觉与选中/焦点语言）

## 1. 背景（Context）

课件环节「关联素材」此前走的是**平台预置 CC0 公共素材包**（`backend/app/features/courseware/seed_cc0.py` + `backend/seeds/courseware_cc0/manifest.json` + 哨兵 owner `COURSEWARE_CC0_OWNER_ID`）：素材库列表里混着「本人上传」与「平台 CC0」两份来源，`search_assets` 用 `own | cc0` 并集，前端还要给 CC0 素材画「平台预置」角标，测试里也要验证这套混合入库逻辑。

这带来几个问题：

1. **来源语义不清**：教师看到的素材库里哪些是自己的、哪些是平台的，需要额外标注；课件挂载的 `asset_id` 指向平台素材时，平台素材一旦被「清理种子」逻辑改动，引用就悬空。
2. **种子链路脆弱**：`manifest.json` + 图片二进制 + 建库期 `ALTER` 加列 + 哨兵 owner 过滤，四段强耦合；改素材 schema 就要同步改种子与迁移，回归面大。
3. **与「资料库」定位重叠**：ADR-0055 已经把「教师上传资料 + 向量化」收口到资料库；课件素材是另一回事（只显示、不向量化），但二者都叫「库」，CC0 又把"预置"这个维度塞进了课件素材，概念被拉歪。

**驱动力**：用户决定把课件素材库简化为**纯教师上传图片**（ADR-0076 已移除 `platform_cc0` 字段与种子），并补一个**独立的素材库入口**，让教师能集中管理自己的图片素材；课件编辑时再用一个**多选 picker** 挑图挂到环节。

## 2. 决策（Decision）

### 2.1 彻底移除平台预置 CC0 概念，素材库 = 纯教师上传

- 删除 `backend/app/features/courseware/seed_cc0.py`、`backend/scripts/seed_courseware_cc0.py`、`backend/seeds/courseware_cc0/`、`backend/tests/features/courseware/test_cc0_ingestion.py`，以及 `CoursewareAsset` 的 `source` / `source_url` / `license` 字段与 `COURSEWARE_ASSET_SOURCE_*`、`COURSEWARE_CC0_OWNER_ID` 常量。
- `search_assets` 只按 `teacher_id` 过滤（不再 `own | cc0` 并集），`delete_asset` 仅 `require_owned`（去掉 CC0 守卫），`asset_file` 改用 `_owned`。
- 迁移 `_add_coursewareasset_cc0_columns` 从 `run_migrations` 摘除并删除函数体（`db.py`）。
- 前端 `CoursewareAssetModel` 删除 `source` / `sourceUrl` / `license` / `isPlatformCc0`，`CoursewareAssetResp` 同步精简；`frontend/test/courseware_editor_page_test.dart` 中 CC0 入库 + 角标用例移除。

### 2.2 新增独立「素材库」侧栏入口（ADR-0059 单源导航）

- `TeacherPage` 新增 `AssetLibraryPage`；`teacher_destinations.dart` 在场景库之后加一项（图标 `LucideIcons.images`，标签「素材库」）；`home_screen.dart` 的 `switch` 补 `AssetLibraryPage() => const AssetLibraryScreen()`（编译器穷尽保证，漏登记即编译失败）。
- 新页面 `asset_library_screen.dart`：**多选上传**（`FilePicker` 选多张图 → 逐张 `uploadAsset`）、**grid 陈列**、**点缩略图放大看原图**（`showImageViewer`）、**逐张删除**（`AppDialog.confirm` 二次确认，删后引用它的环节显示「素材已移除」占位，不级联）。

### 2.3 新增多选素材库 picker（`asset_library_picker.dart`）

- `showAssetLibraryPicker(context, ref, {required List<String> initialSelected})` 返回 `List<String>?`（选中的 asset id）。
- 复用 `coursewareAssetLibraryProvider((knowledgePointId: null, filename: _query))`，支持按文件名检索、内嵌多选上传；确认后回传 id 列表，由调用方按 id 落库。
- 取代旧的单选 `courseware_asset_picker_sheet.dart`（已删除）：旧 picker 用 `{items:[{asset_id,caption}]}` 结构且单张选择，新 picker 一次勾选多张、契约简化为 id 列表。

### 2.4 课件环节「关联素材」改为 grid 缩略图 + 点击放大

- `courseware_section_edit_dialog.dart` 的 `_addAsset` 改用 `showAssetLibraryPicker`：回执 id 列表后保留既有 caption、按 picker 顺序重排、剔除未选、新选给空 caption。
- 选中的素材在编辑弹窗里以 **3 列缩略图网格** 展示（`_materialGrid` + `_MaterialTile`），点缩略图经 `showImageViewer` 放大，右上角删除；素材被删后引用仍在的显示「素材已移除」占位（与 `SectionMediaGallery` 共用 `coursewareAssetsProvider` 解析 id→图）。

### 2.5 共享图片查看器（`app_image_viewer.dart`）

- `showImageViewer(context, {required String url, String? name})`：透明遮罩 + `InteractiveViewer`（双击/双指缩放、拖拽）+ 顶部名称条与关闭按钮；点遮罩或关闭退出。主题无关（白字 + 深色遮罩），素材库 / 课件缩略图 / picker 共用。

## 3. 后果（Consequences）

**正面**

- 素材库来源单一、语义干净：教师只看到自己传的图，无平台兜底、无角标、无种子迁移。
- 入口、picker、查看器三件套可复用：课件编辑与素材库页共用同一份 `coursewareAssetLibraryProvider`，数据一致。
- 「目前做简单点」落实：首版只支持图片上传，刻意不做知识点绑定、不做分类目录、不做 caption 编辑（caption 仅保留展示与回传时的无损传递）。

**负面 / 待办**

- 删素材是破坏性操作：引用它的环节降级为「素材已移除」占位，需教师手动换图（ADR-0067 §4.2 已允许删素材，本 ADR 仅收紧来源）。
- 测试原始素材改用 `resources/images/` 下的 11 张图**手动上传**进 UI 验证，不再有种子脚本；回归时由人工或后续自动化在 UI 走一遍上传流程。
- `asset_library_screen.dart` 当前未纳入自动化截图测试，依赖 `flutter analyze` + 既有 `courseware` 相关用例兜底。

## 4. 替代方案（被否决）

- **保留 CC0 但默认隐藏**：仍要维护种子 + 迁移 + 角标，回归面不降，且「平台素材被删 → 引用悬空」风险仍在，否决。
- **picker 内也支持点击放大**：`AppFocusableAction` 无长按支持，picker 内点击的天然语义是「选择切换」；放大放在选中后的网格与独立素材库页更自然，故 picker 保持纯选择。
- **独立图片查看路由**：引入新路由会增加导航状态面（违反 ADR-0059 单源），且首版用 `Dialog` 覆盖层已足够，否决。
