# 资料库目录管理补全：目录可见性修复 + 移动 / 重命名

## 背景

用户报告两类资料库目录管理问题：

1. 在某目录内新建子目录后，点面包屑「全部」返回根目录时，刚建的目录「消失」。
2. 目录管理是否完整？（创建目录、向新目录上传资料、把**已有资料移入指定目录**）

### 根因（问题 1）

`material_library_provider.createFolder()` 收尾调的是裸 `load()`，而 `load()` 默认
`folderId = null`，会把 `currentFolderId` **重置回根目录**。当用户在某目录内新建子目录时，新目录的
`parent_folder_id` 指向当前目录，但视图被弹回根目录——根目录只渲染 `parentFolderId == null` 的目录，
新建子目录因此不在根视图里，表现为「消失」。

### 完整性盘点（问题 2）

| 能力 | 后端 | 前端 | 状态 |
|---|---|---|---|
| 创建目录 | `POST /folders` ✅ | 新建目录弹窗 ✅ | ✅ |
| 删除目录（非空拦截） | `DELETE /folders/{id}` ✅ | 行内删除 ✅ | ✅ |
| 上传资料到当前目录 | `POST /upload?folder_id` ✅ | 上传资料（用 `currentFolderId`）✅ | ✅ |
| 进入 / 返回目录（面包屑） | `GET /folders` + `GET /materials?folder_id` ✅ | 面包屑「全部」+ 目录行 ✅ | ✅ |
| 目录元数据继承（学科 / 年级 / 学期） | `_resolve_inherited` ✅ | 新建目录弹窗选继承 ✅ | ✅ |
| **把已有资料移入指定目录** | ❌ 无端点 | ❌ 无入口 | ❌ → ✅ 本轮补 |
| **重命名目录** | `PATCH /folders/{id}` ✅ | ❌ 无入口 | ❌ → ✅ 本轮补 |
| **移动目录到其它目录** | `PATCH /folders/{id}`（`parent_folder_id`）✅ | ❌ 无入口 | ❌ → ✅ 本轮补 |

结论：目录 CRUD 的后端能力齐全，但前端缺三类操作入口；最关键的「已有资料归拢进目录」此前完全做不到。

## 决策

- **修复可见性**：`createFolder()` 收尾改 `load(keepFolder: true)`，建完停留当前目录并看到新子目录。
  所有就地刷新动作（`upload` / `vectorize` / `reextract` / `deleteMaterial` / `deleteFolder` /
  `move*` / `rename`）统一用 `keepFolder: true`，保证「在哪操作就在哪刷新」，不再弹回根目录。
- **补 `PATCH /materials/{id}`（移动资料）**：新增 `MaterialMove{folder_id}` schema +
  `service.move_material`；`folder_id = null` 表移回根目录。移动只改归属指针，不触发重新提取 /
  向量化（纯组织操作）；若资料当前缺学科 / 年级且目标目录能提供，则补继承值（让检索按学科过滤仍能命中），
  并把 `ready` 标 `stale` 以便重向量化时再确认。
- **`NetworkService` 补 `patch()`**：抽象类与 `DioNetworkService` 均加 `patch()`，否则现有 folder PATCH
  端点（重命名 / 移动目录）前端也调不到。
- **前端三类操作入口**（`material_library_provider` 新增 `moveMaterial` / `renameFolder` /
  `moveFolder`，仓库层 `moveMaterial` / `updateFolder`）：
  - 资料行加「移动」→ 弹目录树选择器（含「根目录 / 全部」选项）→ `moveMaterial`。
  - 目录行加「重命名」（编辑弹窗：名称 + 学科 / 年级 / 学期，复用新建目录同款字段）与「移动」
    （目录树选择器，**排除自身子树**防成环）→ `renameFolder` / `moveFolder`。
  - 选择器 / 编辑弹窗抽到独立文件 `material_folder_actions.dart`（树形缩进、键盘可达、焦点环沿用
    `AppFocusableAction`），保持 `material_library_view.dart` ≤ 400 行（ADR-0058）。

## 接受的代价

- 移动资料**不自动重向量化**：若资料缺学科 / 年级且目标目录也未提供，则补继承值分支被跳过，检索按学科
  过滤可能仍命中不到其 chunk（既有「上传即无学科」的资料也存在同样情况，非回归）。
- 目录树选择器为简单树形列表（非搜索 / 面包屑回溯），目录量大时是够用的最小实现；后续可加搜索。

## Considered Options

- **问题 1 只在前端加「自动跳回新建目录」**——否（治标；根因是 `load()` 吞掉 folder 上下文，所有就地刷新
  都应保持上下文，一致改成 `keepFolder`）。
- **移动资料改用「删除 + 重新上传」**——否（资料已落盘与向量化，重传浪费且丢 chunk 溯源）。
- **重命名 / 移动目录复用新建目录弹窗**——部分采用（字段同款），但目录树选择器单独实现（排除子树防环）。

## 守卫

- 后端：`tests/api/routes/test_materials.py::TestMaterialLifecycle::test_move_material_to_folder_and_back`
  （移回根 / 移到他目录 / 越权目录 403）通过；`TestFolders` / `TestMaterialLifecycle` 全过。
- 前端：`flutter analyze` 零 issue；`file_size_guard_test`（ADR-0058）通过——
  `material_library_view.dart` 398 行、`material_folder_actions.dart` 247 行，均 ≤ 400。
- ⚠️ `TestVectorization` / `TestVectorRetrieval` 的 3 个失败**与本次改动无关**：`retrieval.py:83`
  `zip()` 长度不匹配是测试假 embedder 的环境 / fixture 问题，已在独立运行确认。

## 与既有 ADR 关系

- **ADR-0055（资料库与 RAG）**：本 ADR 是其 B6 资料库页的目录管理补全，不改动 RAG / 检索语义。
- **ADR-0058（文件规模）**：新增 `material_folder_actions.dart` 走拆分而非加长 `material_library_view.dart`。
