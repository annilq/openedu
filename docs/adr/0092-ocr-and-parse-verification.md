# ADR-0092：资料解析清洗 + 逐页 OCR 兜底 + 上传校验（解决「乱码」与扫描件）

状态：已实现（2026-10-14 · 决策来自 Q1–Q6 回合确认）

> 落地轨迹：`parser.py` 清洗 + 扫描判定 + OCR 兜底 → `Material.parse_meta` + `MaterialResp.parse_warnings`
> → `service.upload_material` 落元数据 → 前端 `material_library_material_row` 校验提示
> → `test_parser.py` / `test_indexing_selfcheck.py` / `test_retrieval_goldset.py`(Hit@1)
> 验证：后端相关测试 15 passed；前端 `material_library_material_row` 新增静默校验行。

## 背景

用户观察到资料库 RAG「生成内容有限」，初判是「教材每知识点内容少」。实测推翻该前提：

- 12 本人教数学 PDF **全部有文本层**（2 万–5.5 万字符/本），正文质量好；
- 真正被当成「乱码」的，是**封面页**的两类噪声：① EAN-13 条码的符号字体（ToUnicode 损坏，
  pypdf 解成私用区码位 `U+E000–F8FF`）；②「绿色印刷产品」防复印水印（解成 `cmmmcmm…` 字母串）。
  二者合计占整本 0.17%–1.18%，**OCR 对它们无效**——条码/水印不是文字，是图形化符号。
- 上一轮误报「四上下册是扫描件」（170/174 字符）是 `app.db` 的历史 stale 脏行；同日入库的
  五上两行解析出 47098 字符，与今日逐字符相等，证明当天代码与现在一致，根因未定（疑当日上传文件
  与 `resources/` 现文件不同一份）。该 4 行已清、重入库（见 §后果）。

结论：**乱码 ≠ 扫描件**，清洗正则即可解决；OCR 是给「家长上传扫描教辅 / 试卷 / 拍照作业」的兜底，
不是当前 12 本的必须项。

## 决策

### 1. 清洗默认开、零新依赖（Q3：先清洗再入库）
`parser.clean_text` 清掉私用区 / 控制符 / 替换符 + 绿印水印长串（`[cm]{5,}`），返回清理字符数。
中文无连续 5+ 的 `c/m`，`cm` 单位仅 2 字符，规则安全。入库前先清洗，乱码 chunk 不进检索。

### 2. OCR 进默认依赖、逐页触发（Q2-A）
`pyproject` 加 `rapidocr` + `onnxruntime` + `pymupdf`（均确认 cp314 / abi3 可装于 Python 3.14）。
**仅真·扫描页触发**：`_pdf_report` 逐页判定（有效文字 < 10 字符 或 未映射字符 > 10，阈值参照
Apache Tika `OcrConfig.StrategyAuto(10,10)`），坏页用 PyMuPDF 光栅化 + RapidOCR 识别。
OCR 引擎与光栅化**懒加载**：缺组件时扫描页退化为告警而非崩溃，应用照常启动。
**公式 / 结构不进本期**（Q1：不上）——人教版算式 / 竖式 / 图形是内容主体，纯 OCR 不输出结构；
本地 MinerU（torch 121MB + 模型 0.8–2GB + server 常驻）与云公式 API（未成年人教材上传第三方）均过重，
留二期，用真实语料暴露的结构缺失案例驱动。

### 3. 上传后解析校验并上 UI（Q5：不加硬门禁，但加验证功能并在 UI 体现）
上传不再因「字符数过少」直接拒收（避免误杀合法资料）。改为：解析全程产出 `ParseReport`
（清理字符数 / 扫描页数 / OCR 页数 / 告警），存入 `Material.parse_meta`；`MaterialResp.parse_warnings`
透传给前端；`material_library_material_row` 在资料行下以静默提示行展示
（「已清理 N 个乱码字符」「检测到 M 页为扫描页，已自动 OCR」「未解析出文字」）。
验证功能 = 解析健康度可观测 + 向量化状态机（pending/ready/failed/stale）已在库，failed 带人话原因。

### 4. RAG 召回以 Hit@1 为主门禁（Q6：Hit@1）
`test_retrieval_goldset.py` 将 **Hit@1 = 100%** 设为主门禁（对排序位置敏感，语料少时分辨力远高于
Recall@5——单知识点仅 3–10 chunk 时 Recall@5 几乎无分辨力）；Recall@5 ≥ 0.85 降为灾难回归护栏。
假 embedding 由 64 维哈希改为 **2048 维 TF 加权哈希**，压住碰撞使 dense 与词法通道一致，
让黄金集真正测「检索代码」而非测替身噪声。

### 5. 修 stale 并重跑入库（Q4）
删除 `app.db` 中 4 行 `pending` 脏数据（2 垃圾 170/174 + 五上重复行，均 0 chunk），用现有
`scripts/ingest_textbooks.py` 重跑 12 本（已先修 stale 再跑）。

## 后果

- **新依赖**：`rapidocr` / `onnxruntime` / `pymupdf` 进默认 `dependencies`，开发机 `uv sync` 重约 100MB。
- **Schema 变更（一次性）**：`material` 表新增 `parse_meta TEXT` 列（`none_as_null` 语义）。
  项目无迁移流程（ADR-0053 不引 alembic），新表靠 `create_all`，旧列靠手动 ALTER——
  已对开发库 `app.db` 执行 `ALTER TABLE material ADD COLUMN parse_meta TEXT;`。
  测试库 `test_app.db` 每次会话重建，自动含该列。
- **上传行为变化**：解析不再静默存空/脏文本；封面噪声被清掉；扫描件自动 OCR；校验告警可见。
- **明确不做**：词法硬门禁 `字符数 < 页数×20 即拒收`（Q5 否）；公式/结构 OCR 二期；灌第三方教辅凑语料。
- **风险**：RapidOCR 对中文印刷体可用，对数学公式 / 竖式 / 图形结构不输出，二期用 MinerU 或云 API 补；
  PyMuPDF/rapidocr 为懒加载，CI 与无 GPU 环境不受影响。

## 未决 / 后续

- 知识点级过滤（kp 精确过滤优先、语义排序兜底）是单点更高杠杆的检索改进，**本期未做**，作为下一步。
- ~~OCR 真实扫描件的端到端验证~~ **已闭环（2026-10-14）**：构造一张「无文本层、仅图片」的扫描页
  PDF，用真实 PyMuPDF 1.28 + RapidOCR 3.10.0 跑通 `_rasterize_and_ocr`——扫描页被正确识别
  （`scan_pages=1` / `ocr_pages=1`），中文文本被准确读出
  （`三年级数学 / 加法运算：27+35=？ / 应用题：小明有12颗糖，妈妈又给了8颗。`），触发
  「检测到 1 页为扫描页，已自动 OCR 识别」告警。验证中发现 RapidOCR ≥3.x 的 `__call__` 返回
  `RapidOCROutput` 数据类（含 `.txts`）而非旧版 `(result, elapsed)` 元组，parser 已改为兼容两种形态。

> 依赖安装坑：开发机原本有一条指向 `localhost:7890` 的死代理，会让 `uv sync` 卡死无输出。
> 改用直连 + 清华镜像即可秒装：`HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=* uv sync
> --index-url https://pypi.tuna.tsinghua.edu.cn/simple`（rapidocr/onnxruntime/pymupdf/opencv
> 共 ~115MB，直连约 30s 装完）。
