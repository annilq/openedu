// 学生卷版面（ADR-0052）。
//
// 这个模板只做「把导出文档画成纸」，不做任何判断：题号、留白形态、有没有选项
// 全部由服务端装配阶段决定（见 app/features/export/document.py）。
//
// 纸面视觉走「轻装饰」：保留墨黑分隔线与学科几何标记（■ ● ▲），**不铺任何彩色
// 填充** —— 家长很可能用黑白激光打印机，色块在那类机器上会印成一团脏灰。

#let data = json(bytes(sys.inputs.data))
#let letters = ("A", "B", "C", "D", "E", "F", "G", "H")

#let ink = luma(30)
#let hairline = luma(140)
#let strike = luma(90)

#set document(title: data.title)
#set page(
  paper: "a4",
  margin: (top: 18mm, bottom: 16mm, left: 20mm, right: 20mm),
  header: [
    #grid(
      columns: (1fr, auto),
      align: (left, right),
      text(size: 9pt, fill: strike)[#data.title],
      // 手填线不用下划线字符（某些字体的下划线字形会贴进基线里，9pt 下几乎不可见），
      // 直接画线，粗细与正文留白线一致。
      text(size: 9pt, fill: strike)[姓名 #box(width: 16mm, height: 3pt, stroke: (bottom: 0.5pt + strike))　日期 #box(width: 16mm, height: 3pt, stroke: (bottom: 0.5pt + strike))],
    )
    #v(-3mm)
    #line(length: 100%, stroke: (paint: hairline, thickness: 0.4pt))
  ],
)
#set text(font: ("Noto Sans SC", "Inter"), size: 12pt, lang: "zh", fill: black)
#set par(leading: 0.5em, justify: false, first-line-indent: 0pt)

#let question(q) = {
  block(
    width: 100%,
    inset: (bottom: 6pt),
    {
      grid(
        columns: (auto, 1fr),
        column-gutter: 4pt,
        text(size: 12pt, weight: "medium")[#q.no.],
        text(size: 12pt)[#q.stem],
      )

      if q.options.len() > 0 {
        pad(left: 14pt, top: 2pt, {
          for (i, opt) in q.options.enumerate() {
            text(size: 11pt)[#letters.at(i). #opt]
            linebreak()
          }
        })
      } else if q.answer_space == "blank_line" {
        // 填空：一条 40mm 横线，写在题干下方而不是塞进题干中间——
        // 服务端不知道题干里哪个位置是空，别在纸上猜位置。
        pad(left: 14pt, top: 4pt, line(length: 40mm, stroke: (paint: ink, thickness: 0.6pt)))
      } else if q.answer_space == "writing_area" {
        // 计算 / 应用：一块带墨黑描边的空白答题区（高度按题型，创作空间够写过程）
        let h = if q.qtype == "open" { 50mm } else { 35mm }
        pad(left: 14pt, top: 4pt, rect(
          width: 100%,
          height: h,
          stroke: (paint: ink, thickness: 0.8pt),
        ))
      }

      v(6pt)
    },
  )
}

#for section in data.sections {
  if section.heading != none {
    v(2pt)
    text(size: 13pt, weight: "bold", fill: ink)[
      #if section.subject_mark != none [#section.subject_mark ]
      #section.heading
    ]
    v(-1mm)
    line(length: 100%, stroke: (paint: ink, thickness: 0.8pt))
    v(6pt)
  }

  for q in section.questions {
    question(q)
  }
}
