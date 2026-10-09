# -*- coding: utf-8 -*-
"""生成教育智能体申报材料：开发报告 / Word模板 / 安装手册 / 使用手册 / 视频脚本。

所有 .docx 按附表3 字体规范：
- 标题：方正小标宋简体 小二(18pt)
- 一级标题：黑体 三号(16pt)
- 二级标题：楷体_GB2312 三号(16pt)
- 三级标题：仿宋_GB2312 三号(16pt)
- 正文：仿宋_GB2312 三号(16pt)，行间距 28磅，首行缩进2字符
"""
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_LINE_SPACING, WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

OUT = "/Users/annilq/Documents/develop/openedu/submission_docs"

TITLE_FONT = "方正小标宋简体"
H1 = "黑体"
H2 = "楷体_GB2312"
H3 = "仿宋_GB2312"
BODY = "仿宋_GB2312"
CODE = "Consolas"

LINE = 28  # 磅


def set_run_font(run, font_name, size, bold=False, color=None):
    run.font.name = font_name
    run.font.size = Pt(size)
    run.font.bold = bold
    if color is not None:
        run.font.color.rgb = color
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:eastAsia"), font_name)
    rfonts.set(qn("w:ascii"), font_name)
    rfonts.set(qn("w:hAnsi"), font_name)


def set_first_indent(p):
    ppr = p._p.get_or_add_pPr()
    ind = ppr.find(qn("w:ind"))
    if ind is None:
        ind = OxmlElement("w:ind")
        ppr.append(ind)
    ind.set(qn("w:firstLineChars"), "2")


def add_para(doc, text="", font=BODY, size=16, bold=False, align=None,
             indent=False, line=LINE, space_after=6, color=None):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    pf = p.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    pf.line_spacing = Pt(line)
    pf.space_after = Pt(space_after)
    if indent:
        set_first_indent(p)
    if text:
        run = p.add_run(text)
        set_run_font(run, font, size, bold, color)
    return p


def add_title(doc, text):
    add_para(doc, text, font=TITLE_FONT, size=18, bold=True,
             align=WD_ALIGN_PARAGRAPH.CENTER, space_after=12)


def add_h1(doc, text):
    add_para(doc, text, font=H1, size=16, bold=True, space_after=8)


def add_h2(doc, text):
    add_para(doc, text, font=H2, size=16, bold=True, space_after=6)


def add_h3(doc, text):
    add_para(doc, text, font=H3, size=16, bold=True, space_after=4)


def add_bullet(doc, text, font=BODY):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    pf.line_spacing = Pt(LINE)
    pf.space_after = Pt(4)
    set_first_indent(p)
    run = p.add_run("• " + text)
    set_run_font(run, font, 16)
    return p


def add_code(doc, text):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    pf.line_spacing = Pt(15)
    pf.space_after = Pt(6)
    pf.left_indent = Pt(18)
    run = p.add_run(text)
    set_run_font(run, CODE, 10.5)
    return p


# ---------------------------------------------------------------------------
# 1. 开发与应用报告
# ---------------------------------------------------------------------------
def gen_report():
    doc = Document()
    add_title(doc, "基于国产大模型与本地部署的中小学错题复习教育智能体设计与应用")

    add_h1(doc, "一、开发背景")
    add_para(doc,
        "当前中小学学习中，学生错题散落于练习册与试卷，缺少系统归类与间隔复习；家长难以讲解、"
        "教师也难以及时掌握班级学情。传统复习依赖人工整理，效率低、易遗漏。国产生成式人工智能"
        "（如 DeepSeek）已具备自动出题、适龄答疑与知识检索能力，且支持本地部署以保护学生隐私、"
        "降低使用门槛。本项目以开源、可复现的方式构建\u201c错题复习教育智能体\u201d，把上述 AI 能力"
        "沉淀为教师可用、可审计、可迁移的教学工具。", indent=True)

    add_h1(doc, "二、设计与开发")
    add_h2(doc, "（一）平台/技术选择")
    add_para(doc,
        "以国产大模型 DeepSeek 为默认引擎（OpenAI 兼容协议，api.deepseek.com），本地 Ollama 为离线备选；"
        "前端采用 Flutter（平板优先），后端采用 FastAPI + SQLModel，数据库使用 SQLite（零依赖）或 PostgreSQL；"
        "通过 Docker 一键本地部署，全部数据留在本机。", indent=True)

    add_h2(doc, "（二）开发过程")
    add_para(doc,
        "1. 提示词工程：抽象\u201c学科人格\u201d配置（subject_personas.py），将语气、适龄、学科约定作为统一参数"
        "注入各业务智能体；出题、答疑、查询分别编写独立的 system prompt 与角色约束，确保输出风格稳定、内容安全。", indent=True)
    add_para(doc,
        "2. 知识库建设：资料库上传教材、卷子、笔记，经切分与向量化（BGE-M3 稠密+稀疏+RRF）构建 RAG 检索；"
        "出题与答疑可引用资料片段并向下游下发\u201c参考来源\u201d，实现有据可查。", indent=True)
    add_para(doc,
        "3. 工作流设计：所有 AI 能力经单一 SSE 入口 POST /api/v1/assistant/chat，由路由分发到四个业务 SubAgent——"
        "query（学情查询，带真实工具调用循环）、question（流式出题）、tutor（伴学答疑）、guide（任务引导），"
        "形成\u201c意图识别→工具取数→结构化卡片\u201d的端到端工作流。", indent=True)
    add_para(doc,
        "4. 代码编写与分层：agent_core 框架无关内核与 app 集成层分离，分层不变量由 CI 静态扫描（AST）守住；"
        "新增一个智能体只需新增一个文件夹，具备良好的可扩展性与可复现性。", indent=True)
    add_para(doc,
        "5. 借助生成式 AI 开发：开发全程使用 DeepSeek / 通义千问辅助编写与调试提示词、生成脚手架代码、"
        "设计工具 schema；关键对话与片段见配套资源中的截图。"
        "［截图位：AI 辅助设计提示词、调试代码、生成脚手架的对话截图］", indent=True)

    add_h2(doc, "（三）功能架构")
    add_bullet(doc, "智能出题：按学科、年级、知识点、题型、难度流式生成题卡（含题干、选项、解析），支持多学科组卷。")
    add_bullet(doc, "伴学答疑：适龄讲解 + 参考来源溯源 + 图形交互演示，内置内容安全闸门。")
    add_bullet(doc, "学情查询：错题本、掌握度、进度、任务等以类型化卡片呈现，结论须由工具数据支撑（无数据即硬失败，杜绝编造）。")
    add_bullet(doc, "间隔复习：按遗忘曲线阶段制 0..4 自动排程，末位阶段答对即毕业。")
    add_bullet(doc, "模型管理：教师自填国产模型 API Key，服务端 Fernet 加密保存，无内置模型、无离线兜底。")

    add_h1(doc, "三、应用过程与效果")
    add_para(doc,
        "本智能体适用于家庭自查与小班课堂两类场景。教师在\u201c模型管理\u201d中添加 DeepSeek 并设为默认后，"
        "即可出题、答疑、查学情；课堂上以\u201c课件练习\u201d模式投屏朗读单题，AI 给分级提示，不落作答记录。", indent=True)
    add_para(doc,
        "［数据位：附学生错题数下降、掌握度提升、课堂参与度等截图或反馈］"
        "预期效益：复习准备时间显著缩短；学生因\u201c分步引导 + 图形演示\u201d提升兴趣与正确率；"
        "教师得以聚焦薄弱知识点讲评，实现教学赋能。", indent=True)

    add_h1(doc, "四、创新与反思")
    add_para(doc,
        "创新点：①业务×学科人格正交组合，单一入口承载出题、答疑、查询；②内核与业务解耦、分层不变量静态守住，"
        "可独立演进；③\u201c反臆造\u201d纪律（查询无工具数据即拦截、答疑仅命中图库才出演示），确保输出可信；"
        "④本地部署、密钥加密，兼顾隐私与合规。", indent=True)
    add_para(doc,
        "存在问题：学习闭环目前仅\u201c答错即建错题\u201d一段打通，出题尚未消费错题与掌握度数据；"
        "AI 能力依赖教师配置模型。下一步：补强闭环（出题吸收薄弱点）、引入多模型协同"
        "（不同 SubAgent 用不同国产模型）、扩展学科与资料知识库、增加使用成效采集看板。", indent=True)

    path = f"{OUT}/开发与应用报告.docx"
    doc.save(path)
    return path


# ---------------------------------------------------------------------------
# 2. Word 模板（预置样式 + 骨架 + 样式对照表）
# ---------------------------------------------------------------------------
def style_set_font(style, name, size, bold=False):
    style.font.name = name
    style.font.size = Pt(size)
    style.font.bold = bold
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:eastAsia"), name)
    rfonts.set(qn("w:ascii"), name)
    rfonts.set(qn("w:hAnsi"), name)


def style_set_line(style, line=LINE):
    pf = style.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    pf.line_spacing = Pt(line)


def gen_template():
    doc = Document()

    # 正文默认样式
    normal = doc.styles["Normal"]
    style_set_font(normal, BODY, 16)
    style_set_line(normal)

    # 预置命名样式
    defs = [
        ("rTitle", TITLE_FONT, 18, True),
        ("rH1", H1, 16, True),
        ("rH2", H2, 16, True),
        ("rH3", H3, 16, True),
        ("rBody", BODY, 16, False),
    ]
    from docx.enum.style import WD_STYLE_TYPE
    made = {}
    for sname, fname, sz, bold in defs:
        st = doc.styles.add_style(sname, WD_STYLE_TYPE.PARAGRAPH)
        style_set_font(st, fname, sz, bold)
        style_set_line(st)
        made[sname] = st

    add_title(doc, "教育智能体设计与应用项目开发与应用报告（标题·方正小标宋简体·小二）")
    add_para(doc, "说明：本模板已预置下列样式，可直接在对应位置输入文字；字体与行距均符合附表3 规范。", font=BODY, indent=True)

    # 样式对照表
    add_h2(doc, "样式对照表（供套用）")
    tbl = doc.add_table(rows=1, cols=3)
    tbl.style = "Table Grid"
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    hdr = tbl.rows[0].cells
    for c, t in zip(hdr, ["样式名", "字体 / 字号", "用途"]):
        c.paragraphs[0].add_run(t)
    rows = [
        ("rTitle", "方正小标宋简体·小二(18pt)", "文档主标题（居中）"),
        ("rH1", "黑体·三号(16pt)", "一级标题，如 一、二、三、四"),
        ("rH2", "楷体_GB2312·三号(16pt)", "二级标题，如 （一）（二）"),
        ("rH3", "仿宋_GB2312·三号(16pt)", "三级标题，如 1. 2. 3."),
        ("rBody", "仿宋_GB2312·三号(16pt)·行距28磅", "正文（首行缩进2字符）"),
    ]
    for name, fs, use in rows:
        cells = tbl.add_row().cells
        cells[0].paragraphs[0].add_run(name)
        cells[1].paragraphs[0].add_run(fs)
        cells[2].paragraphs[0].add_run(use)

    # 骨架
    add_h1(doc, "一、开发背景")
    add_para(doc, "（在此简述本校教学痛点与借助 AI 自主创作的可行性。）", font=BODY, indent=True)
    add_h1(doc, "二、设计与开发")
    add_h2(doc, "（一）平台/技术选择")
    add_para(doc, "（在此说明采用的国产大模型 / 平台 / 框架。）", font=BODY, indent=True)
    add_h2(doc, "（二）开发过程")
    add_para(doc, "（提示词工程、知识库、工作流、代码编写；附关键截图或代码片段。）", font=BODY, indent=True)
    add_h2(doc, "（三）功能架构")
    add_para(doc, "（按模块分类介绍主要功能。）", font=BODY, indent=True)
    add_h1(doc, "三、应用过程与效果")
    add_para(doc, "（结合场景描述应用过程，附数据、学生作品、反馈截图。）", font=BODY, indent=True)
    add_h1(doc, "四、创新与反思")
    add_para(doc, "（创新点、存在问题与下一步改进思路。）", font=BODY, indent=True)

    path = f"{OUT}/教育智能体报告模板.docx"
    doc.save(path)
    return path


# ---------------------------------------------------------------------------
# 3. 安装手册
# ---------------------------------------------------------------------------
def gen_install():
    doc = Document()
    add_title(doc, "安装手册：中小学错题复习教育智能体（本地部署）")

    add_h1(doc, "1. 环境要求")
    add_bullet(doc, "操作系统：macOS / Windows / Linux 均可，推荐 8GB 以上内存。")
    add_bullet(doc, "Flutter SDK ≥ 3.5（CI 锁 3.47.2），用于运行前端平板/桌面端。")
    add_bullet(doc, "Python ≥ 3.14 与 uv（后端依赖管理）。")
    add_bullet(doc, "Docker（可选，用于一键部署；不装也可手动起服）。")
    add_bullet(doc, "一个国产大模型 API Key（推荐 DeepSeek，亦可通义千问 / 智谱 / 豆包 / 本地 Ollama）。")

    add_h1(doc, "2. 获取代码")
    add_code(doc, "git clone <本仓库地址> openedu")
    add_code(doc, "cd openedu")

    add_h1(doc, "3. 后端启动（手动）")
    add_para(doc, "进入后端目录并安装依赖、启动服务：", font=BODY, indent=True)
    add_code(doc, "cd backend")
    add_code(doc, "uv sync")
    add_code(doc, "uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload")
    add_para(doc, "服务起来后，后端地址为 http://<本机局域网IP>:8000 。", font=BODY, indent=True)

    add_h1(doc, "4. 前端启动（手动）")
    add_para(doc, "另开终端，进入前端目录并用本机 IP 注入 API 地址：", font=BODY, indent=True)
    add_code(doc, "cd frontend")
    add_code(doc, "flutter pub get")
    add_code(doc, "flutter run --dart-define=API_BASE=http://<本机IP>:8000")
    add_para(doc, "注意：联调时 API_BASE 必须填电脑局域网 IP，不能填 127.0.0.1，否则真机报\u201c请求失败(-1)\u201d。", font=BODY, indent=True)

    add_h1(doc, "5. Docker 一键部署（推荐）")
    add_code(doc, "docker compose up --build")
    add_para(doc, "容器启动后，前端与后端同机运行，数据保存在本地卷，全程不出本机。", font=BODY, indent=True)

    add_h1(doc, "6. 配置国产模型（DeepSeek）")
    add_bullet(doc, "打开 App，进入\u201c模型管理\u201d页面，点击\u201c添加模型\u201d。")
    add_bullet(doc, "服务商选择 DeepSeek，自动带出 base_url=https://api.deepseek.com。")
    add_bullet(doc, "填写模型名（如 deepseek-v4-flash）与你申请的 sk-... API Key。")
    add_bullet(doc, "把该模型\u201c设为默认\u201d。未配置时出题 / 答疑会提示\u201c未配置模型\u201d。")
    add_bullet(doc, "如需离线，可改用 Ollama：服务商选 Ollama，base_url=http://localhost:11434。")

    add_h1(doc, "7. 常见问题")
    add_bullet(doc, "flutter 命令找不到：将 Flutter SDK 加入 PATH 后重开终端。")
    add_bullet(doc, "后端起不来：确认 Python ≥ 3.14 且 uv sync 成功，端口 8000 未被占用。")
    add_bullet(doc, "AI 不出结果：检查\u201c模型管理\u201d里是否已有默认模型且 Key 有效。")

    path = f"{OUT}/安装手册.docx"
    doc.save(path)
    return path


# ---------------------------------------------------------------------------
# 4. 使用手册
# ---------------------------------------------------------------------------
def gen_usage():
    doc = Document()
    add_title(doc, "使用手册：中小学错题复习教育智能体")

    add_h1(doc, "0. 首次使用：添加国产模型")
    add_para(doc, "进入\u201c模型管理\u201d→\u201c添加模型\u201d，按安装手册第 6 节填入 DeepSeek（或 Ollama），并设为默认。此后所有 AI 功能方可使用。", font=BODY, indent=True)

    add_h1(doc, "1. 教师—智能出题")
    add_bullet(doc, "在 AI 学习助手或出题页选择学科、年级、知识点、题型、数量（一句话也可，如\u201c出3道三年级分数选择题\u201d）。")
    add_bullet(doc, "题目流式生成，逐题审阅；确认后落库，可中途停止或整份重来。")
    add_bullet(doc, "支持多学科组卷，题卡含题干、选项与解析。")

    add_h1(doc, "2. 教师—派发任务")
    add_bullet(doc, "把题目组成任务，派发给单个学生或整班学生。")
    add_bullet(doc, "在任务页查看进度、正确率与连续打卡天数。")

    add_h1(doc, "3. 学生—答题与复习")
    add_bullet(doc, "学生端\u201c今日任务\u201d逐题作答，自动批改并看解析，完成后打卡。")
    add_bullet(doc, "\u201c到期复习\u201d按遗忘曲线把该复习的题推到前面；答错的题进入错题本。")

    add_h1(doc, "4. 伴学答疑（问 AI 老师）")
    add_bullet(doc, "在助手对话框直接提问，AI 给出适龄讲解并标注参考来源。")
    add_bullet(doc, "命中图形知识点时，会先展示交互演示再讲步骤。")
    add_bullet(doc, "内容经安全闸门审核，不合规则拒绝并说明。")

    add_h1(doc, "5. 学情查询")
    add_bullet(doc, "问\u201c小明最近错题多吗\u201d\u201c今天有什么作业\u201d，助手以类型化卡片返回错题本、掌握度、进度等。")
    add_bullet(doc, "所有结论均来自工具真实数据，不编造数字。")

    add_h1(doc, "6. 课堂练习模式")
    add_bullet(doc, "在课件某知识点上开启课堂练习，AI 只生成可投屏朗读的单题。")
    add_bullet(doc, "教师代录学生口答对/错，AI 给分级提示；不落作答记录、不进错题本。")

    add_h1(doc, "7. 打印导出")
    add_bullet(doc, "把题库 / 任务 / 错题排成纸质练习卷（只含题干与作答留白，不含答案），由服务端 Typst 排版导出。")

    path = f"{OUT}/使用手册.docx"
    doc.save(path)
    return path


# ---------------------------------------------------------------------------
# 5. 视频脚本（≤8 分钟）
# ---------------------------------------------------------------------------
def gen_video():
    doc = Document()
    add_title(doc, "演示视频脚本（总时长 ≤ 8 分钟）")

    add_para(doc, "形式：PPT 概述 + App 操作录屏 + 课堂实录片段。画面以录屏为主，关键处加字幕与箭头标注。", font=BODY, indent=True)

    scenes = [
        ("1", "0:00-1:00", "片头 + 案例概述",
         "本校中小学复习痛点：错题散、复习无计划、家长不会讲。本作品是一个基于国产大模型、可本地部署的错题复习教育智能体，覆盖出题、答疑、学情查询、间隔复习。"),
        ("2", "1:00-2:00", "技术选型与本地部署",
         "展示\u201c模型管理\u201d添加 DeepSeek（国产大模型）并设为默认；一句话说明前端 Flutter、后端 FastAPI、本地 Docker 部署，数据不出本机。可放 docker compose 启动录屏。"),
        ("3", "2:00-3:30", "智能出题演示",
         "录屏：在助手输入\u201c出3道四年级分数选择题\u201d，展示流式生成题卡（题干/选项/解析）；说明支持多学科组卷。画面高亮\u201c参考来源\u201d溯源。"),
        ("4", "3:30-5:00", "伴学答疑演示",
         "录屏：学生提问一个错题，AI 给出分步讲解并标注来源；命中图形时展示交互演示。强调适龄、安全闸门。"),
        ("5", "5:00-6:30", "学情查询与复习",
         "录屏：教师问\u201c小明最近错题多吗\u201d，助手返回类型化卡片；切到学生端展示\u201c到期复习\u201d与错题本。强调\u201c结论来自真实数据\u201d。"),
        ("6", "6:30-7:30", "课堂练习模式",
         "录屏：课件某知识点开启课堂练习，投屏朗读单题、AI 分级提示，教师代录口答。说明不落作答记录。"),
        ("7", "7:30-8:00", "应用成效与总结",
         "展示成效截图位（错题下降、掌握度提升、参与度）；总结创新点（单一入口、分层内核、反臆造、本地隐私）与下一步改进。结尾点题：可复现、可迁移的教育智能体。"),
    ]

    tbl = doc.add_table(rows=1, cols=4)
    tbl.style = "Table Grid"
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    for c, t in zip(tbl.rows[0].cells, ["序号", "时长", "画面内容", "旁白脚本"]):
        c.paragraphs[0].add_run(t)
    for no, dur, screen, narr in scenes:
        cells = tbl.add_row().cells
        cells[0].paragraphs[0].add_run(no)
        cells[1].paragraphs[0].add_run(dur)
        cells[2].paragraphs[0].add_run(screen)
        cells[3].paragraphs[0].add_run(narr)

    add_h1(doc, "录制提示")
    add_bullet(doc, "每台机器先授权屏幕录制权限（系统设置→隐私与安全→屏幕录制），首次运行需你在弹窗中批准。")
    add_bullet(doc, "录屏命令示例（macOS，捕获整个屏幕到文件）：")
    add_code(doc, "ffmpeg -f avfoundation -i \"1:0\" -r 30 -video_size 1920x1080 submission_docs/demo.mp4")
    add_bullet(doc, "AI 功能需有效的 DeepSeek API Key；无 Key 时相关录屏会显示\u201c未配置模型\u201d。")

    path = f"{OUT}/视频脚本.docx"
    doc.save(path)
    return path


if __name__ == "__main__":
    files = [gen_report(), gen_template(), gen_install(), gen_usage(), gen_video()]
    for f in files:
        print("wrote", f)
