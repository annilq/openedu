# -*- coding: utf-8 -*-
"""生成教育智能体申报材料：开发报告 / Word模板 / 安装手册 / 使用手册 / 视频脚本。

视频脚本（14 段）的段号、时段与旁白正文从 `narration.md` 读取，与 gen_voice.py /
gen_subs.py 共用同一份事实源；本文件只维护「每段拍什么画面」。

所有 .docx 按附表3 字体规范：
- 标题：方正小标宋简体 小二(18pt)
- 一级标题：黑体 三号(16pt)
- 二级标题：楷体_GB2312 三号(16pt)
- 三级标题：仿宋_GB2312 三号(16pt)
- 正文：仿宋_GB2312 三号(16pt)，行间距 28磅，首行缩进2字符
"""
import re
from pathlib import Path

from docx import Document
from docx.shared import Pt, Cm, RGBColor
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


def set_cell(cell, text, font=BODY, size=10.5, bold=False, align=None,
             line=15, shading=None, first=False):
    """填写表格单元格：显式设字体（表格不继承正文样式，不设会落到西文字体）。
    first=True 复用首段，否则新起一段（多行内容）。"""
    p = cell.paragraphs[0] if first else cell.add_paragraph()
    if align is not None:
        p.alignment = align
    pf = p.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    pf.line_spacing = Pt(line)
    pf.space_after = Pt(2)
    if text:
        run = p.add_run(text)
        set_run_font(run, font, size, bold)
    if shading:
        tcPr = cell._tc.get_or_add_tcPr()
        shd = OxmlElement("w:shd")
        shd.set(qn("w:val"), "clear")
        shd.set(qn("w:color"), "auto")
        shd.set(qn("w:fill"), shading)
        tcPr.append(shd)
    return p


def set_col_widths(table, widths):
    """python-docx 列宽需逐格设置，且要钉住 table.autofit 才不会被重算。"""
    table.autofit = False
    for row in table.rows:
        for cell, w in zip(row.cells, widths):
            cell.width = w


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
    for c, t in zip(tbl.rows[0].cells, ["样式名", "字体 / 字号", "用途"]):
        set_cell(c, t, font=H1, size=10.5, bold=True,
                 align=WD_ALIGN_PARAGRAPH.CENTER, first=True, shading="F2F2F2")
    rows = [
        ("rTitle", "方正小标宋简体·小二(18pt)", "文档主标题（居中）"),
        ("rH1", "黑体·三号(16pt)", "一级标题，如 一、二、三、四"),
        ("rH2", "楷体_GB2312·三号(16pt)", "二级标题，如 （一）（二）"),
        ("rH3", "仿宋_GB2312·三号(16pt)", "三级标题，如 1. 2. 3."),
        ("rBody", "仿宋_GB2312·三号(16pt)·行距28磅", "正文（首行缩进2字符）"),
    ]
    for name, fs, use in rows:
        cells = tbl.add_row().cells
        set_cell(cells[0], name, size=10.5, first=True)
        set_cell(cells[1], fs, size=10.5, first=True)
        set_cell(cells[2], use, size=10.5, first=True)
    set_col_widths(tbl, [Cm(2.3), Cm(6.9), Cm(6.0)])

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
# 5. 视频脚本（14 段 · 总时长 5 分 52 秒 / 红线 6 分钟）
#
# ⚠️ 单一事实源：段号、标题、时段、旁白正文全部从 narration.md 读取
#    （与 gen_voice.py / gen_subs.py 同源），本文件只维护「每一段拍什么画面」。
#    改文案请改 narration.md，不要在下面重复写一遍旁白。
# ---------------------------------------------------------------------------
NARRATION = f"{OUT}/narration.md"
TOTAL_SECONDS = 352          # 14 段合计 5:52
REDLINE_SECONDS = 360        # 红线 6 分钟


def _mmss(sec):
    return f"{int(sec) // 60} 分 {int(sec) % 60:02d} 秒"

# (段号, 端, 画面内容)
VIDEO_SHOTS = [
    (1, "教师",
     "登录页 → 点「没有账号？注册教师账号」→ 依次填 用户名 / 密码 / 昵称 →"
     "「注册并进入」直接落到「工作台」→ 侧栏「我的」退出登录 → 再登录回到工作台"),
    (2, "教师",
     "侧栏「模型管理」→（我的模型为空）→「添加模型」→ 服务商选 DeepSeek，"
     "Base URL 自动带出 → 填模型名与 API Key →「测试连接」等结果条变绿 →"
     "打开「设为默认模型」→ 保存 → 列表出现带「默认」徽标的模型卡"),
    (3, "教师",
     "侧栏「素材库」→ 空态「素材库还是空的」→「上传图片」一次选 2～3 张 →"
     "网格出现缩略图 → 点开一张看原图"),
    (4, "教师",
     "侧栏「资料库」→「上传资料」选 1～3 页的 PDF → 行内点「向量化」等状态变为已向量化 →"
     "切到「知识点管理」，选好 学科 / 年级 / 学期 → 勾选知识点 →「确认选中 (N)」"),
    (5, "教师",
     "侧栏「场景库」→ 场景卡列表 → 点开一张进详情「场景实例」，看库默认演示图形 →"
     "「关联知识点」选一个第 4 段提取的知识点"),
    (6, "教师",
     "侧栏「课件」→ 空态「还没有课件」→「新增课件」选知识点 →「创建空课件」"
     "（此步不触发 AI）→「AI 补充讲解」等环节草案生成 →「开始讲课」进全屏演示 →"
     "方向键翻 2～3 页 → 叫出「问 AI 老师」现场答疑 →「退出演示」"),
    (7, "教师",
     "侧栏「学生」→ 标题「学生管理」，右上角展示「添加学生 / 下载导入模板 / 批量导入」→"
     "「添加学生」填 学生昵称 / 登录账号 / 密码 / 年级 →「创建学生账号」→"
     "点进该学生详情，展示「概览 / 错题本 / AI 答疑」三页签"),
    (8, "教师",
     "侧栏「任务」→「发布任务」→ 派发目标勾选学生 → 试卷标题「今日练习」、总题数 4 →"
     "选 学科 / 知识点 / 题型 → 选出题模型 →「生成」（题卡逐张流式浮现）→"
     "「确认」落库为草稿 →「草稿审核」快速扫一眼 →「锁定并派发」"),
    (9, "学生",
     "教师端退出登录 → 用学生账号在同一个登录页登录 → 自动落到学生端「首页」，"
     "左侧栏变为 5 项（首页 / 复习 / 错题本 / 问 AI 老师 / 掌握度）→"
     "复习错题横幅 → 问 AI 老师横幅 → 今日任务 →「开始做题」，做 2 题（一对一错）→ 完成打卡"),
    (10, "学生",
     "侧栏「复习」→ 顶栏「复习 N/M」→ 作答 →「提交复习」→ 结果弹窗"
     "（答对：下次 N 天后复习；答错：重新计时）→ 继续下一题 → 完成态「复习完成！正确率 X%」"),
    (11, "学生",
     "侧栏「错题本」→ 标题「我的错题本」→ 顺次扫过卡片标签：学科 / 知识点 / 错过 N 次 /"
     "复习阶段 N，以及「最近答错」「下次复习」两个日期"),
    (12, "学生",
     "侧栏「问 AI 老师」→ 输入框（占位「输入你的学习问题…」）输入一道题的问题 →"
     "「发送」，回答逐字流式输出 → 点「按住 说话」松开，展示语音提问"),
    (13, "学生",
     "侧栏「掌握度」→ 标题「我的学科掌握度」→ 汇总行「你已掌握 N / M 个知识点」→"
     "顺次扫过各知识点的进度条：X 分、等级徽章（已掌握 / 较扎实 / 薄弱 / 待加强）、"
     "正确率与待复习题数"),
    (14, "教师",
     "退出登录 → 用教师账号重新登录 → 侧栏「概览」（页内标题「工作台」）→"
     "待办三张卡（待审核 / 待派发 / 谁没交）→「最近任务」→ 学情速览（掌握度环形、"
     "薄弱知识点、正确率）→ 学情分析把「统计范围」切一次维度，图表跟着变"),
]

# 录制过程中会真实等待的 5 处（剪辑时的处理口径）
WAITS = [
    ("第 2 段 · 测试连接", "3～10 s", "保留原速——这是「真的连上了」的证据，出来后停 1 s 再继续"),
    ("第 4 段 · 向量化", "10 s～数分钟", "后期加速 2～4 倍，或只留「点击 → 已向量化」两端"),
    ("第 6 段 · AI 补充讲解", "5～20 s", "后期加速 2 倍"),
    ("第 8 段 · 生成（流式出题）", "15～40 s", "不要剪、不要加速——逐题浮现本身就是亮点"),
    ("第 12 段 · AI 回答（流式）", "5～20 s", "后期加速 2 倍；这是学生段「AI 活着」的唯一证据"),
]

# 每段的时长红线（超了就重录，剪辑能加速但补不了镜头）
REDLINES = {
    1: 32, 2: 50, 3: 22, 4: 38, 5: 28, 6: 50, 7: 32,
    8: 52, 9: 32, 10: 30, 11: 25, 12: 32, 13: 26, 14: 35,
}

_HEAD = re.compile(r"^##\s+(\d+)\s*·\s*(.+?)（(.+?)）\s*$")


def load_narration(path=NARRATION):
    """解析 narration.md → {段号: (标题, 起止时段, 旁白正文)}。"""
    segs, cur = {}, None
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        s = line.strip()
        m = _HEAD.match(s)
        if m:
            cur = int(m.group(1))
            segs[cur] = (m.group(2).strip(), m.group(3).strip(), [])
        elif cur is not None and s and not s.startswith(">"):
            segs[cur][2].append(s)
    return {k: (t, span, "".join(body)) for k, (t, span, body) in segs.items()}


def gen_video():
    nars = load_narration()
    missing = [no for no, _, _ in VIDEO_SHOTS if no not in nars]
    if missing:
        print(f"  ⚠️ narration.md 缺少第 {missing} 段（请保持与 VIDEO_SHOTS 一致）")

    doc = Document()
    add_title(doc, f"演示视频脚本（14 段 · 总时长 {_mmss(TOTAL_SECONDS)}）")

    add_para(doc,
        "形式：App 操作录屏为主，关键处叠加字幕与箭头标注，配中文旁白音轨。全片 14 段，"
        "按「教师端 9 段 + 学生端 5 段」的顺序推进，逐段单独录制、单独出字幕，最后按序拼接。"
        f"总时长 {_mmss(TOTAL_SECONDS)}（{TOTAL_SECONDS} 秒），红线 {REDLINE_SECONDS // 60} 分钟。",
        indent=True)
    add_para(doc,
        "时长口径：每段时长 = 该段配音实测时长 + 动作余量（点按与必须展示的等待）。"
        "旁白语速按 4.76 字/秒（zh-CN-XiaoxiaoNeural）测算，录制时动作跟随旁白同步进行。", indent=True)

    add_h1(doc, "一、分镜表")
    # 列宽上限取「Letter 默认页边距」的可用宽度 15.24cm，换 A4 也不会溢出
    widths = [Cm(0.9), Cm(1.8), Cm(1.0), Cm(5.4), Cm(6.1)]
    tbl = doc.add_table(rows=1, cols=5)
    tbl.style = "Table Grid"
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    for c, t in zip(tbl.rows[0].cells, ["序号", "时段", "端", "画面内容", "旁白脚本"]):
        set_cell(c, t, font=H1, size=10.5, bold=True,
                 align=WD_ALIGN_PARAGRAPH.CENTER, first=True, shading="F2F2F2")

    for no, side, screen in VIDEO_SHOTS:
        title, span, narr = nars.get(no, ("", "", ""))
        cells = tbl.add_row().cells
        set_cell(cells[0], f"{no}", size=10.5, align=WD_ALIGN_PARAGRAPH.CENTER, first=True)
        set_cell(cells[1], span, size=10.5, align=WD_ALIGN_PARAGRAPH.CENTER, first=True)
        set_cell(cells[2], side, size=10.5, align=WD_ALIGN_PARAGRAPH.CENTER, first=True)
        set_cell(cells[3], f"\u3010{title}\u3011{screen}", size=10.5, first=True)
        set_cell(cells[4], narr, size=10.5, first=True)
    set_col_widths(tbl, widths)

    add_h1(doc, "二、时长红线")
    add_para(doc, "录完一段先对红线，超了就重录——剪辑能加速，但不能补镜头。", indent=True)
    rt = doc.add_table(rows=1, cols=4)
    rt.style = "Table Grid"
    rt.alignment = WD_TABLE_ALIGNMENT.CENTER
    for c, t in zip(rt.rows[0].cells, ["序号", "环节", "目标时长", "红线"]):
        set_cell(c, t, font=H1, size=10.5, bold=True,
                 align=WD_ALIGN_PARAGRAPH.CENTER, first=True, shading="F2F2F2")
    for no, side, _ in VIDEO_SHOTS:
        title, span, _ = nars.get(no, ("", "", ""))
        dur = ""
        m = re.match(r".*–(.*)", span)
        if m:
            end = m.group(1)
            em, es = (int(x) for x in end.split(":"))
            prev = "0:00"
            if no > 1:
                _, pspan, _ = nars.get(no - 1, ("", "", ""))
                prev = re.match(r".*–(.*)", pspan).group(1)
            pm, ps = (int(x) for x in prev.split(":"))
            dur = f"{(em * 60 + es) - (pm * 60 + ps)} s"
        cells = rt.add_row().cells
        set_cell(cells[0], str(no), size=10.5, align=WD_ALIGN_PARAGRAPH.CENTER, first=True)
        set_cell(cells[1], f"{title}（{side}）", size=10.5, first=True)
        set_cell(cells[2], dur, size=10.5, align=WD_ALIGN_PARAGRAPH.CENTER, first=True)
        set_cell(cells[3], f"≤ {REDLINES[no]} s", size=10.5,
                 align=WD_ALIGN_PARAGRAPH.CENTER, first=True)
    set_col_widths(rt, [Cm(1.1), Cm(8.5), Cm(2.5), Cm(3.1)])

    add_h1(doc, "三、等待时间怎么处理")
    wt = doc.add_table(rows=1, cols=3)
    wt.style = "Table Grid"
    wt.alignment = WD_TABLE_ALIGNMENT.CENTER
    for c, t in zip(wt.rows[0].cells, ["位置", "大概等多久", "处理"]):
        set_cell(c, t, font=H1, size=10.5, bold=True,
                 align=WD_ALIGN_PARAGRAPH.CENTER, first=True, shading="F2F2F2")
    for where, dur, how in WAITS:
        cells = wt.add_row().cells
        set_cell(cells[0], where, size=10.5, first=True)
        set_cell(cells[1], dur, size=10.5, align=WD_ALIGN_PARAGRAPH.CENTER, first=True)
        set_cell(cells[2], how, size=10.5, first=True)
    set_col_widths(wt, [Cm(4.4), Cm(2.5), Cm(8.3)])

    add_h1(doc, "四、录制与合成")
    add_bullet(doc, "分段录制，一段一个文件：")
    add_code(doc, "DURATION=60 ./submission_docs/record_app.sh 6   # 录第 6 段 → submission_docs/raw/demo_06.mov")
    add_bullet(doc, "窗口建议 ≥1280×800，且宽度保持 ≥700——学生端窄于此会从左侧栏切成底部 Tab 栏，画面跳档。")
    add_bullet(doc, "首次运行需授权「屏幕录制」权限（系统设置 → 隐私与安全性 → 屏幕录制），否则录成黑屏。")
    add_bullet(doc, "录前清屏：关闭聊天窗口与通知（开勿扰模式）；鼠标点击已默认高亮显示。")
    add_bullet(doc, "一条命令出成片（字幕 + 配音 + 变速贴合 + 合并）：")
    add_code(doc, "cd submission_docs && python gen_subs.py --all                # → final_demo.mp4")
    add_bullet(doc, "脚本量的是每段实际录屏与配音时长，把画面变速去贴合配音（视频长→加速、视频短→减速并定格补足），"
                    "字幕时间轴即配音时长；无需再手工对齐。")
    add_bullet(doc, "AI 相关段落依赖「模型管理」中已配置并测试通过的默认模型；未配置时相关录屏会显示「未配置模型」。")
    add_bullet(doc, "旁白文案单一事实源为 narration.md，改动后先重跑 gen_voice.py（配音）、再跑 gen_subs.py（字幕与合成）。")

    path = f"{OUT}/视频脚本.docx"
    doc.save(path)
    return path


if __name__ == "__main__":
    # 使用手册 / 安装手册 / 开发记录 / 开发与应用报告 已改为由 md2docx.py 从同名 .md 生成
    # （单一事实源，内容面向非专业读者且控制字数）。这里不再生成这四份，
    # 避免用旧的偏技术内容把它们覆盖回去。
    files = [gen_template(), gen_video()]
    for f in files:
        print("wrote", f)
