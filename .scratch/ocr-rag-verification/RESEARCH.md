# 资料库 OCR + 向量化验证 + RAG 召回验证 · 一手资料调研

> 视角：后端可行性 + 验收方法。范围：`backend/app/features/materials/`（解析 / 向量化 / 检索三件事的「怎么做」与「怎么验」）。
> 方法：只采一手来源——官方文档、GitHub REST API、PyPI JSON API、arXiv 摘要、本仓代码（`file:line`）。版本与数字均为 2026-10-14 当日查询结果。区分标注：**[实测]**（wheel 内容、PyPI/GitHub API 应答、在本机跑出来的数字）、**[官方]**（项目方文档 / README / 论文自称）、**[推断]**（基于一手事实的推理）。
>
> **⚠️ 第 0.1 节为 2026-10-14 当晚的复核结论，它推翻了本报告初版「扫描件」的判定，并改变了第 2、5 节的推荐。先读第 0.1 节。**
> 背景事实（委托方实测，直接采用，未重新验证）：`resources/` 12 本人教数学教材 PDF 约 300MB；已入库 4 本，`LENGTH(text)` 为 170 / 174 / 47098 / 47098；前两本（四上下册）只抽出封面与条码乱码（形如 `૫^OJOEE^A^A...`），是扫描/图片型 PDF；`materialchunk` 表 0 行，4 本 `index_state` 全 `pending`。

---

## 0.1 复核结论：这 12 本 PDF 不是扫描件，乱码也不是 OCR 能修的（2026-10-14 晚，[实测]）

初版报告据「DB 里 四上/四下 `LENGTH(text)` = 170/174 字符」判定为扫描件。**该判定错误**：那两行是**过期脏数据**，不是源文件的性质。当晚用本仓 `parser.extract_text()` 直接对 `resources/*.pdf` 重跑，12 本全部成功：

| 书 | 页数 | extract_text 字符数 | 字符/页 | <10 字符的页 | 乱码字符 | 乱码占比 |
|---|---|---|---|---|---|---|
| 一上 | 118 | 20749 | 174.9 | 2 | 86 | 0.41% |
| 三上 | 122 | 34214 | 279.5 | 0 | 84 | 0.25% |
| 二上 | 115 | 29846 | 258.5 | 1 | 85 | 0.28% |
| 五上 | 124 | 47098 | 378.8 | 0 | 128 | 0.27% |
| 六上 | 126 | 49421 | 391.2 | 3 | 85 | 0.17% |
| 四上 | 126 | **43856** | 347.1 | 2 | 516 | 1.18% |
| 一下 | 110 | 22484 | 203.4 | 6 | 96 | 0.43% |
| 三下 | 118 | 37268 | 314.8 | 3 | 95 | 0.25% |
| 二下 | 130 | 34002 | 260.6 | 6 | 93 | 0.27% |
| 五下 | 131 | 54942 | 418.4 | 1 | 436 | 0.79% |
| 六下 | 122 | 50591 | 413.7 | 4 | 93 | 0.18% |
| 四下 | 123 | **39779** | 322.4 | 5 | 110 | 0.28% |

四条硬事实：

1. **12 本全部有文本层**，pypdf 6.19.0 每本抽出 2.1 万–5.5 万字符，正文质量好（四上中段抽样可见「速度 × 时间 = 路程」等干净课文与例题）。
2. **DB 里 170/174 那两行是脏数据**。同一次实测里 五上 extract_text = 47098，与 DB 行**逐字符相等**，证明 DB 行的写入时点与当前解析一致；而 四上/四下 当前解析得 43856/39779，与 DB 的 170/174 相差 99.6%——这两行写于更早的解析尝试（旧 pypdf 版本或旧代码），之后从未重跑。**这不是扫描件证据，是没重跑的 stale 行。**
3. **乱码总量 0.17%–1.18%，且集中在封面一页**，来源是两个东西：
   - **EAN-13 条码的符号字体**：``（12 本全有，85–130 字符）——条码字体的 ToUnicode CMap 坏了，pypdf 把条码解成私用区码位。
   - **「绿色印刷产品」防复印水印字体**：`cmmmcmmmmmcmmcmmmmmcmmcmmmccmcmcm`（四上 516 字符、五下 436 字符）——水印字形没有可用 ToUnicode，被解成字母噪声。
4. **OCR 修不了这两类乱码**。条码和水印不是文字，是图形/符号字体渲染。对封面做 OCR 只会得到同样或更差的噪声（条码甚至可能被 OCR 成随机数字污染检索）。

**因此本节把任务重新定义为**：①清掉封面页的条码 + 水印噪声（正则即可，零新依赖）；②把 12 本重新向量化（当前 `materialchunk` 0 行、全 `pending` 才是 RAG 没生效的真因）；③OCR 降级为**面向未来家长上传扫描教辅/试卷的可选能力**，不是当前 12 本的解药。第 2 节选型结论仍成立（它回答的是「将来真要 OCR 时选什么」），但第 5 节落地顺序据此重写。

### 0.1.1 stale 行的根因：未定论（诚实记录）

四上/四下 两行 `text` 为何只有 170/174 字符，**未找到确定解释** [未验证]。已排除的假设与证据：

- **不是 pypdf 版本差异**：`pypdf>=6.19.0` 于 2026-10-04（`a44f115`）引入且此后未变；4 行资料创建于 2026-10-09，`五上` 两行同日解析得 47098 字符（与今日逐字符相等），说明当日代码/依赖与今日一致。
- **不是代码截断**：`service.py:277` 直接存 `extract_text()` 全量返回值，`upload_material` 无长度裁剪；`parser.py:38` 的 `_MAX_TEXT_CHARS = 200_000` 也远未触及。
- **不是文件大小**：四上 22.7MB / 四下 14.9MB / 五上 25.7MB，与解析结果无相关（最大的五上解析最完整）。
- **剩余可能**：当日上传的文件与今日 `resources/` 下的不是同一份（如下载中断后换过文件），或上传过程中字节损坏。**无法从现有证据判定。**

**工程含义**：无论根因是什么，它都会复发——上传路径没有任何「文本量异常」的自检。这正是第 3.2 节自检断言要堵的洞：解析出的字符数低于「页数 × 阈值」时就地报警，而不是默默存一行 170 字符的 `text` 然后 `pending` 到永远。

---

## 0. 一句话结论

**判定用「每页字符数 + 乱码率」双阈值（Tika 默认 <10 字符/页 或 >10 个未映射 Unicode/页即判扫描，官方源码可查）；混合 PDF 只 OCR 坏页是 ocrmypdf / PyMuPDF / Tika 三方官方文档一致支持的逐页策略。选型结论：RapidOCR 3.10.0（ONNX/PP-OCRv6，进程内，Apache-2.0）是 Python 3.14 + macOS arm64 + 无 GPU 约束下唯一同时满足「装得上、跑得动、许可证干净」的本地引擎；PaddleOCR 系因 paddlepaddle 无 cp314 wheel 出局，MinerU 装得上但 2GB 模型 + 8GB RAM + server 形态超出解析器一步到位的范畴，公式结构建议二期单独处理。向量化自检写成 9 组 pytest 断言（第 3 节清单）；RAG 评测在「一个知识点 3–10 个 chunk」的规模下 Recall@5 已接近恒真，应换 MRR / nDCG@k + 干扰 chunk 拒绝断言——本仓现有 Recall@5 ≥ 0.85 门禁在真实语料上来之前几乎没有分辨力。**

---

## 1. Q1：什么情况下该用 OCR，怎么判定

### 1.1 三个候选解析库的官方失败模式说明

| 库 | 官方原话（节选） | 来源 |
|---|---|---|
| pypdf | "If a PDF page appears to contain only an image (e.g., a scanned document), the extracted text may be minimal or visually empty. In such cases, consider using OCR software such as Tesseract OCR" | [pypdf docs · Extract Text](https://pypdf.readthedocs.io/en/latest/user/extract-text.html) |
| pypdf | "pypdf is **not** OCR software."；"pypdf will never be able to extract text from images." | 同上 |
| pypdf | "Then there are PDF files that contain an image and a text layer in the background. That typically happens when a document was scanned. Although the scanning software (OCR) is pretty good today, it still fails once in a while. **pypdf is no OCR software; it will not be able to detect those failures.**" | 同上 |
| pypdf | 三分法：Digitally born / Scanned / OCRed；"If you scan a document... it's recommended to directly use OCR software as errors can accumulate" | 同上 |
| pdfplumber | "Works best on machine-generated, rather than scanned, PDFs."；不提供的功能包括 "Optical character recognition (OCR)" | [pdfplumber README](https://github.com/jsvine/pdfplumber) |
| PyMuPDF | "Determine whether OCR is needed / beneficial at all. A number of criteria can be used for this decision, like: **page is completely covered by an image / no text exists on the page / thousands of small vector graphics (indicating simulated text)**" | [PyMuPDF docs · OCR recipes](https://pymupdf.readthedocs.io/en/latest/recipes-ocr.html) |
| PyMuPDF | "Because optical character recognition is about one thousand times slower than standard text extraction, we make sure to do OCR only once per page and store the result in a TextPage" | 同上 |

**对本仓案例的直接解释** [推断]：四上下册抽出 170/174 字符且形如条码乱码，正是 pypdf 文档说的 "minimal or visually empty" 与「隐藏 OCR 层错字且无法检测失败」两种情形的叠加——当前 `parser.py:48` 的 `page.extract_text() or ""` 既不判空（整篇 join 后被 `parser.py:36-37` 的 strip 检查放行，因为乱码非空），也不判质量。170 字符不是「读出来一点」，是**该页无文本层 + 条码区噪声**的典型签名。

### 1.2 开源项目检测「扫描件」的通行做法（阈值量级 + 出处）

| 判据 | 数值 / 做法 | 一手来源 |
|---|---|---|
| 每页字符数 | **< 10 字符/页 → OCR**（默认值 `StrategyAuto(10, 10)`：每页总字符 < 10，或每页未映射 Unicode 字符 > 10，即对该页 OCR） | Apache Tika `OcrConfig.java` 源码 [实测] + [PDFParserConfig.OCRStrategyAuto javadoc](https://tika.apache.org/3.2.1/api/org/apache/tika/parser/pdf/PDFParserConfig.OCRStrategyAuto.html)："If the total characters on the page < this.totalCharsPerPage or total unmapped unicode characters on the page > this.unmappedUnicodeCharsPerPage then we will perform OCR on the page" |
| 每页乱码率 | 同上：未映射 Unicode 绝对数 >10（或比例版 `FASTER = (0.1f, 10)` 即 >10%） | Tika `OcrConfig.java`（`BETTER = new StrategyAuto(10, 10); FASTER = new StrategyAuto(0.1f, 10)`）[实测] |
| 图像覆盖整页 / 无文本 / 海量小矢量图形 | 定性三条，满足即 OCR | [PyMuPDF OCR recipes](https://pymupdf.readthedocs.io/en/latest/recipes-ocr.html) [官方] |
| XObject image 枚举机制 | `page.images`："Get a list of all images on the page"（含 XObject form 内嵌套图） | [pypdf PageObject 文档](https://pypdf.readthedocs.io/en/latest/modules/PageObject.html) [官方] |
| 整篇策略（非逐页） | unstructured 官方博客称 Auto 策略 "dynamically choosing the best parsing approach per page"；hi_res 策略默认不处理扫描页内文字（需显式配 OCR） | [unstructured 官方博客](https://unstructured.io/blog/mastering-pdf-transformation-strategies-with-unstructured-part-2)（项目方一手，但属营销文体，无数值阈值） |

**未找到一手来源的**：①「/Font 资源缺失 → 扫描件」的数值化开源实现——PyMuPDF 有 `page.get_fonts()` API 且 recipe 给的是定性 criteria（"no text exists on the page"），但没找到任何项目把「无 /Font」单独做成阈值判据；②docling 旧版曾有的 `bitmap_area_threshold`（图像占比阈值）默认值——在当前 docling 源码 `docling/datamodel/pipeline_options.py` 中 grep 未命中该参数（已重构为 `OcrMode.FULL_PAGE` 开关 + `force_full_page_ocr` 弃用提示）[实测]，故不引用其数值。

### 1.3 可落地判定启发式（建议写进 `parser.py` 二期）

```
输入：pypdf PdfReader（已有依赖，无需新增）
对每页 p：
    chars   = len(p.extract_text() or "")
    unmapped = 不可映射 Unicode 字符数（私有区/替换符/控制符）
    imgs    = len(p.images)          # pypdf 官方 API
判定：
    坏页  ⇔  chars < 10 或 unmapped > 10        # Tika 默认阈值，量级最权威
    辅助信号（不单独定罪）：imgs ≥ 1 且 chars < 50；无 /Font 资源（pypdf 无直接 API，需读 /Resources）
文档级：
    坏页占比 ≥ 50% → 整本按扫描件走 OCR 管线（进度可见、可中断）
    坏页占比 < 50% → 混合 PDF，只 OCR 坏页（见 1.4）
```

阈值量级依据 [官方]：Tika 默认 10 字符/页。教材正文页实测量级为 200–800 字符/页（由 47098 字符/本 ÷ 页数推算 [推断]），扫描页 0–30 字符，10 这条线两侧各有一个数量级余量。**注意封面 / 目录 / 条码页天然少字符**——所以文档级看分布（坏页占比），不看单页绝对值；这是对 Tika 逐页规则的必要修正 [推断]。

### 1.4 混合 PDF：只 OCR 坏页 vs 整本重 OCR

三方官方文档一致支持**逐页决策、只处理坏页**：

1. **ocrmypdf**（MPL-2.0，35k stars）："If `--mode skip` (or `--skip-text`) is issued, then no image processing or OCR will be performed on pages that already have text. The page will be copied to the output. **This may be useful for documents that contain both 'born digital' and scanned content**"；另有 `--mode redo`：先把可见/不可见文本分类、剥掉旧隐藏 OCR 层再重识别，"If a file contains a mix of text and bitmap images that contain text, OCRmyPDF will locate the additional text in images without disrupting the existing text."（[ocrmypdf docs](https://ocrmypdf.readthedocs.io/en/latest/advanced.html) [官方]）
2. **PyMuPDF**：`page.get_textpage_ocr(full=False)` 即「只 OCR 无有效文本的区域」；v1.27.2 起部分 OCR 覆盖「合法文本以外的所有区域，含矢量图形与乱码文本区」（[Page 文档](https://pymupdf.readthedocs.io/en/latest/page.html) [官方]）。
3. **Tika**：`AUTO` 策略本质就是逐页判定（见 1.2）[官方]。

**结论 [推断]**：只 OCR 坏页，不整本重 OCR。三条理由：①好页的文本层是精确的（pypdf 原话："pypdf will never confuse characters. It just reads what is in the file."，OCR 反而引入错误）；②PyMuPDF 官方数据 OCR 比文本提取慢约 1000 倍，300MB 教材整本重 OCR 在无 GPU 的 Mac 上不可行；③ocrmypdf 的 `--mode redo` 场景（图上有字 + 隐藏 OCR 层）只适用于「已有 OCR 层但质量差」的文件，本仓四年级案例没有隐藏层，用不到。

**只 OCR 坏页的四个工程陷阱** [推断，均有官方事实支撑]：
- **阅读顺序**：PyMuPDF 明说部分 OCR 产出的文字 "will follow (legible) normal text... and will thus not be in reading order"，拼接时要按页序 + 区序自己组织。
- **页边界**：逐页 OCR 后必须插页分隔符再交给 `chunker.py:24-46`（它按空行分段），否则跨页段落粘连。
- **乱码层污染**：对「图像 + 隐藏 OCR 层」型 PDF，pypdf 会稳定吐出错字且不报错（1.1 节原话）——判定逻辑要能识别这类（低 chars + 高 unmapped 即坏页，走 OCR 而非信文本层）。
- **幂等**：OCR 结果按 `(文件 sha256, OCR 引擎版本)` 缓存，重跑上传/重向量化不重复烧 CPU；这与 `indexing.py:79-84` 的「全量重建先删后写」是两层，互不替代。

---

## 2. Q2：OCR 库选型

### 2.1 逐项档案

#### A. PaddleOCR / PaddleOCR-VL（PaddlePaddle 生态）

- **许可证**：Apache-2.0（[GitHub API](https://api.github.com/repos/PaddlePaddle/PaddleOCR) [实测]）。
- **安装体积 / 依赖链** [实测 PyPI]：`paddleocr` 3.7.0（2026-06-11）本体仅 0.14MB，但依赖 `paddlex[ocr-core]` 3.7.2 → `paddlepaddle` 3.3.1（2026-03-26）。macOS arm64 wheel `paddlepaddle-3.3.1-cp3XX-cp3XX-macosx_11_0_arm64.whl` **104.5MB/个**；模型另计（PP-OCRv6 medium 34.5M 参数 [官方 README]；PaddleOCR-VL-0.9B 权重约 GB 级 [推断，README 未给体积]）。
- **macOS arm64 / Python 3.14** [实测]：arm64 wheel 只有 cp39–cp313 五个 tag（`cp310/311/312/313/39`），**无 cp314**。本仓 `backend/pyproject.toml` 要求 `requires-python = ">=3.14,<4.0"` → **实际不可用**（除非源码编译 PaddlePaddle，等于自绝于「不引入编译型重依赖」的约束）。README badge 自称 python 3.8~3.12，与 PyPI 元数据（`requires_python: >=3.8` 无上限）互相矛盾，以 wheel tag 实测为准。
- **进程模型**：进程内 Python 库。
- **中文 / benchmark** [官方 README 自称]：PP-OCRv6 medium 较 v5_server "+4.6% detection and +5.1% recognition"，"surpassing mainstream Vision-Language Models"；Apple M4 上 tiny 档 6.1× 加速。**未给出简体中文印刷体绝对 CER 数字**。PaddleOCR-VL-1.6 自称 "96.3% accuracy on OmniDocBench v1.6"（README 原文；[论文摘要](https://arxiv.org/abs/2510.14528) 只给定性 SOTA 表述，无数字）。
- **公式支持**：PaddleOCR-VL（0.9B VLM，NaViT 视觉编码器 + ERNIE-4.5-0.3B）明确支持 "text, tables, formulas, and charts" 识别 [官方]；PP-StructureV3 提供表格单元格坐标 [官方]。
- **维护活跃度** [实测]：91,083 stars；最新 release v3.7.0（2026-06-11）；最近 push 2026-09-16。

#### B. RapidOCR（onnxruntime 路线）

- **许可证**：Apache-2.0（代码与模型均是；README 明示模型权重源自 PaddleOCR、Apache-2.0 再分发）[实测 GitHub API + README]。
- **安装体积 / 依赖链** [实测]：`rapidocr` 3.10.0 wheel 为 `py3-none-any`、**27.29MB，内置模型**（解包 wheel 验证：`PP-OCRv6_det_small.onnx` 9.9MB + `PP-OCRv6_rec_small.onnx` 21.2MB + `ch_ppocr_mobile_v2.0_cls_mobile.onnx` 0.6MB）；推理后端可插拔（README：`pip install rapidocr onnxruntime`；Docker 段列出 onnxruntime / openvino / paddle / tensorrt / pytorch / mnn 多后端）。依赖：pyclipper、opencv-python-headless、numpy<3、Shapely、PyYAML、Pillow、omegaconf 等。
- **macOS arm64 / Python 3.14** [实测]：`requires_python: <4,>=3.8` 声明支持 3.14；onnxruntime 1.31.0 有 cp314 arm64 wheel（`onnxruntime-1.31.0-cp314-cp314-macosx_14_0_arm64.whl`，20.88MB）；opencv-python-headless 是 cp37-abi3 wheel（覆盖 3.14）；numpy 2.5.4、Shapely 2.2.0 有 cp314 arm64 wheel；**pyclipper 1.4.0 亦有 cp314 wheel**（`pyclipper-1.4.0-cp314-cp314-macosx_10_15_universal2.whl`，0.3MB）——初版报告误判为「无 cp314 wheel 需源码编译」，复核 PyPI JSON API 后更正：**整条依赖链零编译**。另注意 docling 官方文档提示 "RapidOCR has known issues with read-only filesystems"（[docling pipeline_options.py docstring](https://github.com/docling-project/docling) [实测]）——容器/CI 只读挂载场景要避开。
- **进程模型**：进程内 Python 库（`from rapidocr import RapidOCR; engine = RapidOCR()`）。
- **中文 / benchmark**：无自有 benchmark（模型即 PP-OCRv6 small，官方数字归 PaddleOCR，见 A 项）[推断]。默认模型覆盖 ch/chinese_cht/en/japan + 40 余拉丁语种（wheel 内 `default_models.yaml` [实测]）。
- **公式支持**：**无**——只有检测 + 方向分类 + 识别三件套（PP-OCR 系），公式/竖式/表格结构一概不输出 [实测 wheel 内容]。
- **维护活跃度** [实测]：8,135 stars；最新 release v3.10.0（2026-10-08，六天前）；最近 push 2026-10-14（当日）。
- 附：旧包 `rapidocr-onnxruntime` 1.4.4 最后上传 2025-01-17，`requires_python` 为 `<3.13` → Py3.14 **不可用**，已实质停更 [实测]。

#### C. Tesseract + `chi_sim`

- **许可证**：Apache-2.0（[GitHub API](https://api.github.com/repos/tesseract-ocr/tesseract) [实测]）。
- **安装体积 / 依赖链** [实测]：非 Python 包——`brew install tesseract`（5.5.3，bottle 覆盖 macOS Apple Silicon ✅），仅含 eng/osd 语言数据；中文需 `brew install tesseract-lang`（tessdata_fast）。`chi_sim.traineddata`：tessdata（fast）42.31MB / tessdata_best 12.47MB [实测 GitHub API]。Python 侧 `pytesseract` 0.3.13（2024-08-16）只是 30KB 的包装器。
- **macOS arm64 / Python 3.14**：与 Python 版本完全解耦（子进程二进制），**无兼容性问题** [实测 Homebrew bottle]。
- **进程模型**：**子进程**（pytesseract 每次调用 spawn `tesseract` 二进制；PyMuPDF 的 OCR 集成同样外呼 Tesseract）。
- **中文 benchmark**：**未找到一手来源**——tessdoc 与 release notes 均无中文 CER 数字（只有 "fast/best" 两档训练数据的定性取舍）。
- **公式支持**：无。且 PyMuPDF 官方明说 "Tesseract does not recognize vector graphics (i.e. no drawings / line-art)"——教材的竖式、几何图形、表格线全部丢失 [官方]。
- **维护活跃度** [实测]：76,982 stars；5.5.3（2026-07-24）；最近 push 2026-10-10。

#### D. MinerU / Magic-PDF（PDF 结构化解析）

- **许可证**：**MinerU Open Source License = Apache-2.0 + 附加条款**（`LICENSE.md` [实测原文]）：可商用；但 MAU > 1 亿或月收入 > 2000 万美元需单独商业授权；对第三方提供在线服务必须显著标注使用了 MinerU。注意旧包 `magic-pdf` 1.3.12 是 **AGPL-3.0** [实测 PyPI]——许可证口径两个包不同，别混。
- **安装体积 / 依赖链** [实测]：`mineru` 4.0.12 wheel 3.5MB；**macOS arm64 自动拉 `mineru[torch]`**（PyPI 环境标记 `sys_platform == "darwin" and platform_machine == "arm64"`，torch 2.14.1 arm64 wheel 121.4MB）；模型下载 basic 档 ~0.8GB / standard·advanced 档 ~2GB；最低 RAM 2GB（basic ONNX）/ 8GB（standard ONNX+llama.cpp）（README 原表 [官方]）。
- **macOS arm64 / Python 3.14** [实测]：`requires_python: <3.15,>=3.10` ✅；依赖链 wheel 均为 cp310-abi3（docvortex 0.5.16、mineru-llama-cpp 0.1.3 都有 `macosx_11_0_arm64` / `macosx_14_0_arm64` abi3 wheel）或纯 Python → **3.14 装得上**。README 明说 "on macOS the default install is already the best-throughput package and `[full]` is not needed"，Apple Silicon 推荐 standard 档（PyTorch + llama.cpp Vulkan）。
- **进程模型**：CLI + 本地后台 server（`mineru server start`，多数命令走本地服务）+ Python SDK（`DoclibClient`）——**不是**一个 import 即用的进程内函数 [官方 README]。
- **中文 / benchmark**：无中文绝对数字。论文自称 SOTA：MinerU2.5（1.2B VLM，两阶段解析）[arXiv:2509.22186](https://arxiv.org/abs/2509.22186)、MinerU2.5-Pro [arXiv:2604.04771](https://arxiv.org/abs/2604.04771)，摘要均只给定性表述。
- **公式支持**：支持——README 明示适用于 "documents contain OCR text, tables, formulas, figures or complex page layouts"，公式输出 LaTeX（渲染目标含 LaTeX）[官方]。
- **维护活跃度** [实测]：81,721 stars；最新 release 4.0.12（2026-10-11）；最近 push 2026-10-14。
- 附：`magic-pdf` 1.3.12 上传于 2025-05-24 后停更，且 `requires_python: <3.14` → Py3.14 **不可用**，已被 `mineru` 包取代 [实测]。

#### E. 云 API（百度 / 腾讯 / Azure Document Intelligence / Google Document AI）

| 服务 | 公式支持（一手证据） | 许可证 / 计费 | 进程模型 | 活跃度 / 状态 |
|---|---|---|---|---|
| 腾讯云 OCR | **数学公式识别 FormulaOCR**："支持识别主流初高中数学符号和公式，返回公式的 Latex 格式文本"，限速 5 次/秒（[文档](https://cloud.tencent.com/document/product/1009/38293)）；教育版公式识别 "可支持理科（数学、物理、化学、生物）的印刷体和手写体的公式识别"，支持 PDF 输入（`IsPdf`/`PdfPageNumber`），限速 2 次/秒（[文档](https://cloud.tencent.cn/document/product/1323/115929)） | 商业 ToS，按量付费 + 需企业实名 | 远程 HTTP | 文档持续更新 [官方] |
| Azure Document Intelligence | `ocr.formula` 能力："extracts all identified formulas... as a top level object under content... its LaTeX representation as value"，`prebuilt-layout` + `api-version=2024-11-30`；**注意坑**："The confidence score is hard-coded"（[add-on capabilities](https://learn.microsoft.com/en-us/azure/ai-services/document-intelligence/concept/add-on-capabilities?view=doc-intel-4.0.0)） | 商业 ToS，按量付费 | 远程 HTTP | GA [官方] |
| Google Document AI | Enterprise Document OCR v2.0（`pretrained-ocr-v2.0-2023-06-02`）premium add-on `ENABLE_MATH_OCR`："Turn on the model that can extract LaTeX math formulas"，输出 `page.math_formulas`；支持中文（zh）（[Enterprise Document OCR 文档](https://cloud.google.com/document-ai/docs/process-documents-ocr)、[release notes](https://cloud.google.com/document-ai/docs/release-notes)） | 商业 ToS，按量付费（premium add-on 另计费） | 远程 HTTP | GA [官方] |
| 百度智能云 OCR | 公式识别接口返回 LaTeX，但页面顶部公告：**"该接口已停止更新且即将下线，为避免影响您目前的业务使用，请您及时进行相关迁移工作"**（更新时间 2026-02-26）（[文档](https://cloud.baidu.com/doc/OCR/s/Ok3h7xxva)） | 商业 ToS | 远程 HTTP | **接口将下线** [官方] |

**云 API 的三个共性判断** [推断]：①都需要独立的云厂商密钥 + 付费，与项目「家长自带 LLM model api_key」的模式不兼容（那是 LLM key，不是 OCR 密钥）；②12 本教材扫描件是未成年人教学材料，上传第三方云有合规风险，本地单机开发场景应默认本地处理；③除腾讯 / Azure / Google 的公式接口外，通用印刷体识别没有一家给出可引用的中文 CER 数字（**未找到一手来源**）。

### 2.2 对比表

约束基线：本地单机开发（macOS arm64）、无 GPU、Python ≥3.14（`backend/pyproject.toml`）、不引入需编译 CUDA 的重依赖、家长自带 LLM key、教材含大量算式/竖式/图形题。

| 维度 | PaddleOCR 3.7 | RapidOCR 3.10 | Tesseract 5.5.3 | MinerU 4.0.12 | 云 API |
|---|---|---|---|---|---|
| 许可证 | Apache-2.0 | Apache-2.0 | Apache-2.0 | Apache-2.0+附加条款（旧 magic-pdf 为 AGPL） | 商业 ToS |
| 安装体积（本地增量） | ~104.5MB（paddlepaddle wheel）+ 模型 | **27.3MB wheel 含模型** + onnxruntime 20.9MB，零编译 | brew 二进制 + chi_sim 12–42MB | 3.5MB wheel + torch 121.4MB + 模型 0.8–2GB | 0 |
| macOS arm64 | ✅（cp9–13 wheel） | ✅（pyclipper 需编译一次） | ✅（brew bottle） | ✅（abi3 wheel） | — |
| **Python 3.14** | ❌ **无 cp314 wheel** | ✅ 声明 <4,≥3.8；pyclipper 需源码编译 | ✅ 与 Python 解耦 | ✅ `<3.15,≥3.10` | — |
| 无 GPU 可跑 | ✅（CPU） | ✅（CPU，ONNX） | ✅（CPU） | ✅（basic/standard 档 CPU；8GB RAM） | — |
| 进程模型 | 进程内 | **进程内** | 子进程 | CLI + 本地 server | 远程 HTTP |
| 简体中文印刷体数字 | 官方自称 +4.6%/+5.1%（无绝对 CER） | 无自有数字（继承 PP-OCRv6） | **未找到一手来源** | 无（论文自称 SOTA） | 未找到 |
| 数学公式 | ✅（VL 档，LaTeX） | ❌ | ❌（且不认矢量图形） | ✅（LaTeX） | ✅（腾讯/Azure/Google；百度将下线） |
| 竖式/表格结构 | ✅（VL/PP-StructureV3） | ❌ | ❌ | ✅ | 部分（表格） |
| 维护活跃度 | 91k★，v3.7.0@2026-06 | 8.1k★，v3.10.0@2026-10-08 | 77k★，5.5.3@2026-07 | 82k★，4.0.12@2026-10-11 | — |

### 2.3 推荐

**一期（现在，但注意第 0.1 节）：RapidOCR 3.10.0 + onnxruntime，作为 `parser.py` 的图片型 PDF 兜底路径。** 理由（按约束排序）：

1. Python 3.14 是硬约束：PaddlePaddle 无 cp314 wheel 直接出局；rapidocr-onnxruntime 旧包 `<3.13` 出局；Tesseract/MinerU/RapidOCR 过线。
2. 本地单机 + 无 GPU：27.3MB wheel 自带 PP-OCRv6 small 模型，纯 CPU ONNX 推理，装完即用——相比 MinerU 的 2GB 模型 + 8GB RAM + server 常驻，契合「解析器里的一步」而非「一套新基础设施」。**且依赖链零编译（pyclipper 有 cp314 wheel）。**
3. 许可证干净：Apache-2.0，无 AGPL / 无 MAU 条款 / 无署名义务（MinerU 有附加条款，magic-pdf 是 AGPL）。
4. 参照系：RapidOCR 模型即 PP-OCRv6（PaddleOCR 官方模型转 ONNX），其中文能力与 PaddleOCR 同源——选 RapidOCR 损失的只是 PaddleX 的文档解析管线，不是识别质量本身 [推断]。
5. **但对当前 12 本人教教材，一期不需要启用它**（第 0.1 节）：这 12 本全部有文本层，OCR 路径保持关闭/未触发即可。它是为家长上传的扫描教辅、试卷、手写作业拍照准备的兜底。

**公式与结构（二期，单独决策）**：小学数学教材的算式、竖式、图形题是内容主体，纯 OCR 必然丢结构。两条路：①本地 MinerU standard 档（隐私最好；代价是 2GB 模型 + llama.cpp Vulkan + server 形态，且 Apple Silicon 上 README 自称默认即最优）；②腾讯云公式识别（唯一在文档里明确写「初高中数学」+ LaTeX + 支持 PDF 的接口；代价是密钥/付费/上传合规）。**建议先用 RapidOCR 把 12 本的文本层跑出来、用第 3/4 节的自检和黄金集验证检索链路，公式增强等真实语料暴露出结构缺失的具体案例后再上**——现在上重依赖属于为想象中的需求付费 [推断]。

**明确不推荐**：PaddleOCR/PaddlePaddle（Py3.14 无 wheel，且引入 ~100MB 编译生态）；magic-pdf（AGPL + Py<3.14 + 停更）；Tesseract 作主引擎（中文印刷体无官方数字兜底、不认矢量图形、子进程管理成本；留作 RapidOCR 的 A/B 对照基线即可）；百度公式接口（官方公告即将下线）。

---

## 3. Q3：怎样验证知识库成功向量化

### 3.1 本仓已有保证（代码即证据）

| 保证 | 位置 |
|---|---|
| 向量与文本一一对应（批次数不等即炸） | `indexing.py:85` `zip(pieces, vectors, strict=True)` |
| float32 小端定长编码 | `indexing.py:34-36` |
| 全量重建：重向量化先删旧片，杜绝两个向量空间混存 | `indexing.py:79-84`（注释自述） |
| 每 chunk 落 `embed_model` + `chunker_ver` 版本戳 | `indexing.py:93-94` |
| Material 行同步版本戳 + `indexed_at` | `indexing.py:100-103` |
| 检索侧按版本戳过滤（双保险） | `retrieval.py:122-123` |
| 模型/切分器变更 → stale 惰性标记 | `indexing.py:110-135` |
| embedding 失败落 failed 态带人话原因，不抛 500 | `indexing.py:52-58, 74-77` |
| 失败路径不毁旧数据：先 `embed_texts` 成功才删旧片 | `indexing.py:74-84`（顺序即保证） |

外部依据 [官方]：Ollama embedding 文档明示 "The `/api/embed` endpoint returns **L2-normalized (unit-length)** vectors"、"**Use the same embedding model for both indexing and querying**"、"The vector length depends on the model (typically 384–1024 dimensions)"（[docs.ollama.com](https://docs.ollama.com/capabilities/embeddings)）——本仓 `embed_model` 版本戳机制正是这条官方建议的落地；L2 归一化则是「零向量断言」的依据（归一化端点不应产出零向量，除非输入为空/异常）。

### 3.2 入库自检断言清单（可直接写成 pytest，`tests/features/materials/test_indexing_selfcheck.py`）

前置：fixture 造 1 个 teacher + 1 份 subject/grade 齐全、`text` 长度 > 2000 字符的资料；monkeypatch `embed_texts` 返回确定性假向量（照抄 `test_retrieval_goldset.py:35-44` 的词袋替身，或固定种子的伪随机）。

| # | 断言 | 写法要点 | 依据 |
|---|---|---|---|
| 1 | chunk 数与切分器一致 | `pieces == chunk_text(text)`（同输入同输出，切分器确定性）；DB 行数 `== len(pieces)` | `chunker.py:23` 纯函数 |
| 2 | 数量关系合理 | `1 <= len(pieces) <= ceil(len(text)/ (_TARGET_CHARS - _OVERLAP_CHARS)) + 段落修正`；总量守恒：`abs(sum(len(c) for c in pieces) - len(text)) <= (len(pieces)-1) * _OVERLAP_CHARS * 1.5` | 算术恒等式 [推断] |
| 3 | 维度一致 | 每个 `len(vec) == EMBED_DIM`（配置常量）；`len(chunk.embedding) == EMBED_DIM * 4` | Ollama 文档「维度随模型」+ `encode_vector` 定长 |
| 4 | 无 NaN / 无零向量 | `not any(math.isnan(x) or math.isinf(x) for x in vec)`；`norm(vec) > 1e-6`；provider=ollama 时加严：`abs(norm - 1.0) < 1e-3` | Ollama 文档 L2 归一化 [官方]；NaN 检查为通行工程实践（无单一权威来源，见第 6 节） |
| 5 | 版本戳全齐 | `SELECT DISTINCT embed_model, chunker_ver FROM materialchunk WHERE material_id=...` 单行且等于 `(settings.EMBEDDING_MODEL, CHUNKER_VERSION)`；Material 行同——防半截写入 | `indexing.py:93-101` |
| 6 | 余弦 sanity check | 同资料相邻 chunk 平均余弦 > 跨资料随机对平均余弦（假向量下用固定语料自编，或真 provider 下用小样本 + 容忍带）；断言「同文近、异文远」不反号 | 通行实践 [推断]；`retrieval.py:81-86` 已有余弦实现可复用 |
| 7 | 幂等重跑 | 连续两次 `vectorize_material` → chunk 数、content 集合、`indexed_at` 外全部字段一致；无重复 seq | `indexing.py:79-84` 全量重建 |
| 8 | 失败路径无损（建议补） | 第一次注入 `EmbeddingUnavailableError` → `index_state == failed`、`index_error` 非空、**旧 chunk 原样保留**、`indexed_at` 不变 | `indexing.py:74-84` 顺序 |
| 9 | 状态机迁移 | pending→ready；换 `EMBEDDING_MODEL` 后 `mark_stale_if_model_changed` 返回 ≥1 且状态为 stale，再 vectorize 回 ready | `indexing.py:110-135` |

**对本仓 4 本 pending 资料的即时意义**：断言 1–4 现在就能在真实 embedding provider 配好后跑（47098 字符那两本会产生 ~90+ chunk，是现成的自检素材）；断言 5 的「版本戳单行」查询可以直接对着 `materialchunk` 表现跑——0 行的表跑不出任何结论，这也解释了为什么「向量化从未跑通」一直没被发现：**没有自检，pending 和 ready 看起来都一样** [推断]。

---

## 4. Q4：怎样验证 RAG 召回准确

### 4.1 指标定义与适用场景（Manning《Introduction to Information Retrieval》第 8 章，官方在线版）

| 指标 | 定义（教材原话节选） | 适用场景 | 来源 |
|---|---|---|---|
| Precision / Recall | "Precision is the fraction of retrieved documents that are relevant... Recall is the fraction of relevant documents that are retrieved"；"you can always get a recall of 1 (but very low precision) by retrieving all documents for all queries! **Recall is a non-decreasing function of the number of documents retrieved**" | 集合型，无排序信息；召回随返回数单调不减 | [IR book §8.2](https://nlp.stanford.edu/IR-book/html/htmledition/evaluation-of-unranked-retrieval-sets-1.html) |
| P@K / Recall@K | "Set a rank threshold K; Compute % relevant in top K - Ignores documents ranked lower than K" | 只看前 K 条；K 大时 Recall@K 易饱和 | [Stanford CS276 课件（引 IIR §8）](https://web.stanford.edu/class/cs276/handouts/lecture8-evaluation_2013_1_per_page.pdf) |
| MAP | "Among evaluation measures, **MAP has been shown to have especially good discrimination and stability**" | 多查询聚合、排序敏感 | [IR book §8.3](https://nlp.stanford.edu/IR-book/html/htmledition/evaluation-of-ranked-retrieval-results-1.html) |
| MRR | 首个相关文档排位的倒数均值（通行定义）；教材课件将 MRR 与 P@K、MAP 并列为二元相关性下的排序指标，LlamaIndex 文档亦以 "ranking metrics like mean-reciprocal rank (MRR), hit-rate" 描述检索评测 | 「知识点→唯一 chunk」形态；本仓出题管线 query = knowledge_point 正是此形态 | [IR book 课件](https://web.stanford.edu/class/cs276/handouts/lecture8-evaluation_2013_1_per_page.pdf)；[LlamaIndex docs](https://developers.llamaindex.ai/python/framework/module_guides/evaluating/) |
| nDCG@k | "NDCG is **designed for situations of non-binary notions of relevance**... evaluated over some number k of top search results" | 多级相关度；top 位置加权 | [IR book §8.4](https://nlp.stanford.edu/IR-book/html/htmledition/evaluation-of-ranked-retrieval-results-1.html) |
| BEIR 标准 | "we... compute **nDCG@10** for all datasets"（论文原文，[ar5iv 全文](https://ar5iv.labs.arxiv.org/html/2104.08663)） | 学术界检索评测默认口径 | [BEIR arXiv:2104.08663](https://arxiv.org/abs/2104.08663) |

### 4.2 黄金集标注流程与稀疏标注

流程（教材原文为依据）[官方]：
1. **设计信息需求**："These information needs are best designed by domain experts. Using random combinations of query terms as an information need is generally not a good idea"——即查询应由懂教学的人从真实用法（学生提问、知识点名）中归纳，不是随机词组合。本仓 `_GOLD` 的「知识点即查询」一类（`test_retrieval_goldset.py:237-240`）符合这条。
2. **相关性标注是昂贵的人工**："This is a time-consuming and expensive process involving human beings"——所以只标相关、不穷举不相关，是学界标准做法而非偷懒。
3. **Pooling（稀疏标注的学理基础）**："relevance is assessed over a subset of the collection that is formed from the top k documents returned by a number of different IR systems"（IR book §8.5）。黄金集只标「相关 chunk」= pooling 的手工子集。
4. **标注一致性**：kappa 统计，"above 0.8 good agreement, 0.67–0.8 fair"（IR book §8.5）——单人标注时无法计算，双人复核 10% 样本即可估计。

**稀疏标注下的指标选择** [官方定义 + 推断]：只标相关 chunk 时，precision 的分母（检索到的「不相关」数）不可知——precision / P@k / nDCG 的绝对值都失真。**可用的是 recall 族（Recall@k / Hit@k）与排序族中不依赖未标注文档的形式（MRR、首位命中）**；nDCG 用二元 gain 时同样受未标注文档影响（排进 top-k 的未标注文档按 0 分还是忽略，需固定口径并声明）。本仓现有黄金集正是稀疏标注，其 Recall@5 / Hit@5 的选择与此一致。

### 4.3 RAGAS / LlamaIndex evaluation 在「无 GPU + 不联网 CI + 语料少」下的适用性

| 框架 | 官方原文 | 结论 |
|---|---|---|
| RAGAS | "**LLM Based metrics might use one or more LLM calls** to arrive at the score or result"（[metrics 总览](https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/)）——Context Precision / Context Recall / Faithfulness / Answer Relevancy 全部在列 | **不适用 CI**：这些指标需要 judge LLM，无 GPU 不联网跑不了；且需要 LLM 密钥（与「不联网」互斥）。其非 LLM 指标（BLEU/ROUGE/Exact Match）对检索评测无意义。可在本地开发环境接 ollama 做抽检，不进 CI [推断] |
| LlamaIndex | Response Evaluation："LlamaIndex offers **LLM-based** evaluation modules... This uses a 'gold' LLM (e.g. GPT-4)"；Retrieval Evaluation："evaluate retrieved results using **ranking metrics**"，但数据集生成是 "synthetically generate (question, context) pairs"（[docs](https://developers.llamaindex.ai/python/framework/module_guides/evaluating/)） | **部分适用**：黄金集手工标好之后，其 retrieval 评测部分（MRR / hit-rate）是纯本地计算，可进 CI；合成问题生成与 response 评测依赖 LLM，不可进 CI |

**结论**：本仓「固定语料 + 确定性假 embedding + 纯 pytest」的路线（`test_retrieval_goldset.py:1-13` 自述设计）在约束下是正确选择，不需要引入 RAGAS/LlamaIndex。二者值得借鉴的是方法论而非依赖：LlamaIndex 把「dataset → ranking metrics」分离的做法，与本仓黄金集结构同构。

### 4.4 特别问题：一个知识点只有 3–10 个 chunk 时，Recall@5 还有没有分辨力

**基本没有。** 一手依据 + 算术原因：IR book 原话 "**Recall is a non-decreasing function of the number of documents retrieved**" 且 "you can always get a recall of 1 (but very low precision) by retrieving all documents for all queries"（[§8.2](https://nlp.stanford.edu/IR-book/html/htmledition/evaluation-of-unranked-retrieval-sets-1.html)）——k 相对 gold 数越大，Recall@k 越接近恒真 [官方定义 + 推断]。当 subject+grade 过滤后候选池只有 3–10 个 chunk、gold 占其中 3–10 个时，top-5 随便排都能盖住大部分 gold——Recall@5 逼近 1，Hit@5 更早饱和（gold=1 时 top-5 命中概率 ~5/N）。此时 Recall@5 ≥ 0.85 的门禁近似恒真，**它能防「彻底坏掉」，不能防「轻微退化」**（换 embed 模型、调 chunker 导致排序劣化 10–20%，指标动都不动）。本仓现有语料 19 chunk / 每查询 gold 1–3 个（`test_retrieval_goldset.py:48-241`），已处在这个区间；真实教材 OCR 后单科单年级 chunk 数上千，Recall@5 会恢复分辨力——**两个阶段应该用两套门禁**。

**该换什么（按优先级）**：

1. **MRR@k 或首位命中率（Hit@1）**：对排序位置敏感，3–10 chunk 规模下仍有量程。MRR 是「单一相关文档」场景的标准指标（IR book 课件 / LlamaIndex docs），与出题管线「query = knowledge_point」形态匹配。
2. **干扰 chunk 拒绝断言（语料少时最有效的构造）**：从同学科同年级的**相邻知识点** chunk 作 hard negatives（黄金集「跨资料干扰」一类已在做：`test_retrieval_goldset.py:222-235`），断言 gold 排名高于全部干扰 chunk、或「前 2 条不含相邻知识点」。这把评测从「召回」切换到「区分」——precision 的手工近似，绕开未标注文档问题 [推断，依据 IR book precision 定义]。
3. **nDCG@k（二元 gain）**：top 位置加权，BEIR 标准口径（nDCG@10）；注意固定「未标注文档计 0 还是忽略」的口径并写进测试 docstring。
4. **MAP**：IR book 原话 "especially good discrimination and stability"，多 gold 查询下比单点指标稳。
5. **保留 Recall@5 作为回归护栏**（防灾难性回退），但门禁旁边必须并列 MRR / 拒绝断言——单一指标在这个规模下不构成质量信号。

---

## 5. 落地顺序（按依赖排序，已按第 0.1 节复核结论重写）

| # | 项 | 优先级 | 依赖 | 备注 |
|---|---|---|---|---|
| 0 | **清洗封面页乱码**：条码符号字体 + 防复印水印字体的噪声正则（私用区 + 控制符 + 长串字母水印），零新依赖 | P0 | 无 | 第 0.1 节实测乱码仅占 0.17%–1.18%，一条正则解决；**这不是 OCR 的活** |
| 1 | **重新向量化 12 本**（先修 四上/四下 两行 stale `text`，再跑 ingest） | P0 | 0 | 当前 `materialchunk` 0 行、全 `pending`，这才是 RAG 失效的真因 |
| 2 | 第 3.2 节自检断言落 `tests/features/materials/test_indexing_selfcheck.py` | P0 | 1 | 没有自检，pending 和 ready 看起来一样 |
| 3 | 黄金集补 MRR + 干扰拒绝断言（4.4 节），Recall@5 降为回归护栏 | P1 | 2 | 真实语料上来前门禁的主要分辨力来源 |
| 4 | `parser.py` 加逐页扫描判定（Tika 阈值 + pypdf `page.images`），坏页走 RapidOCR；`rapidocr` + `onnxruntime` 进 backend 可选依赖组 | P1 | 2 | 判定逻辑可先于引擎上线；引擎做成 optional extra，不拖累默认安装 |
| 5 | 公式/结构增强（MinerU standard 或腾讯公式 API） | P2 | 2、3、4 有基线后 | 用真实语料暴露的具体案例驱动，不预先上重依赖 |

**建议批次**：`0` 单独一提交（正则清洗 + 单测）；`1` 一提交（含 stale 行修复）；`2+3` 一提交；`4` 一提交；`5` 等语料。

**明确不做**：给当前 12 本人教教材上 OCR（第 0.1 节：全部有文本层，乱码 OCR 修不了，只会更慢更脏）。

---

## 6. 未找到一手来源的清单（诚实清单）

1. **Tesseract 对简体中文印刷体的 CER / 准确率官方数字**——tessdoc、release notes、GitHub 均无（只有 tessdata fast/best 的定性取舍）。
2. **RapidOCR 对简体中文印刷体的自有 benchmark**——项目无 benchmark 页，其数字继承 PaddleOCR PP-OCRv6（官方数字见 PaddleOCR README，但为相对提升非绝对 CER）。
3. **PaddleOCR-VL / MinerU 的中文绝对准确率**——只有 OmniDocBench 的官方自称值（PaddleOCR-VL-1.6 96.3%）与论文定性 SOTA 表述。
4. **「/Font 资源缺失」作为扫描判据的数值化开源实现**——PyMuPDF recipe 只有定性三条；无项目把字体缺失单独做成阈值。
5. **docling 旧版 `bitmap_area_threshold` 的默认值**——当前 docling 源码中该参数已不存在（重构为 `OcrMode`），未核实旧版默认数值，故未引用。
6. **unstructured Auto 策略的逐页判定数值**——官方博客只有定性描述，未读其源码验证。
7. **零向量 / NaN 检查的权威文档依据**——通行工程实践，无单一权威一手来源；本报告以 Ollama「L2 归一化」官方声明作为部分支撑。
8. **Azure DI / Google DocAI 的中文识别准确率数字**——两家官方文档均无中文 benchmark 数字。
9. **百度公式识别接口的具体下线日期**——官方页面只写「即将下线」，无时间表。
10. **PaddleOCR-VL-0.9B 的模型权重体积**——README 与论文摘要均未给（仅能推断为 GB 级）。

---

## 7. 决策落地（2026-10-14 · 来自 Q1–Q6 回合确认）

调研结论被用户决策部分覆盖，实际落地如下（对应 `ADR-0092`）：

| 议题 | §5 调研建议 | 实际决策（Q1–Q6） | 差异 |
|---|---|---|---|
| OCR 依赖位置 | P1 · optional extra（不拖累默认安装） | **Q2-A · 进默认 `dependencies`** | 用户选 A：自动逐页检测 + 坏页自动 OCR 默认开启 |
| 公式/结构 OCR | P2 · 二期 | **Q1 · 不上** | 一致：本地 MinerU / 云 API 过重，留二期 |
| 乱码处理 | P0 · 正则清洗封面 | **Q3 · 先清洗再入库**（已实现 `clean_text`） | 一致 |
| 向量化失效真因 | P0 · 重跑 12 本（含修 stale） | **Q4 · 用现有 ingest，先修 stale 再跑**（已执行：删 4 行 pending 脏数据 → 重入库） | 一致 |
| 重入库后验证 | P0 · 自检断言 | **已实现 `test_indexing_selfcheck.py`** | 一致 |
| 上传硬门禁 | （未建议拒收） | **Q5 · 不加硬门禁**，改「解析校验 + UI 呈现」 | 用户否决拒收，要求可观测 |
| RAG 召回指标 | P1 · MRR + 干扰拒绝 | **Q6 · Hit@1 主门禁**（Recall@5 降护栏） | 用户取 Hit@1；干扰拒绝由 Hit@1 隐含覆盖 |

**实测修正的两条核心认知**（推翻调研初始前提）：
1. 12 本 PDF **全有文本层**，乱码是封面条码 + 绿印水印（占 0.17%–1.18%），**OCR 修不了、也无需 OCR**——清洗正则解决；
2. 上一轮「四上下册是扫描件」是 `app.db` 历史 stale 脏行（170/174 字符），非扫描件。

**已交付代码**：`parser.py`（清洗 + 逐页扫描判定 + 懒加载 OCR 兜底）、`Material.parse_meta` + `MaterialResp.parse_warnings`、`service.upload_material` 落元数据、前端 `material_library_material_row` 校验提示行、三套测试（parser 单测 / 向量化自检 / 黄金集 Hit@1）。后端相关测试 15 passed。
