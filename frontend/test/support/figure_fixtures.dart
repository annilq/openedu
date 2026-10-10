// 测试用图形夹具（ADR-0083 T06）。
//
// 为什么需要它：`kFigureShapes` 已随「图库 DB 化」退役（决策 1/7）——几何的事实源是
// `figure_library` 表，前端不再持有「整库」常量。测试里需要「一批图形」时只能自己造，
// 于是把与后端 `BUILTIN_FIGURE_SEED` **同几何**的几个内置图形放这里，给画廊 / 画板 /
// 解释器 / 课件挑图形的用例共用。
//
// ⚠️ 改这里的顶点等于改测试的输入契约：与后端种子对不上的话，`figureLibraryProvider`
// 的解析用例（走 `is_builtin` 行）与实际后端行为就会分叉。
library;

import 'package:kids_learn/shared/domain/figures.dart';

/// 房子（内置 `house`）：五边形，竖轴对称。
const FigureShape kHouseFixture = FigureShape(
  key: 'house',
  label: '房子',
  vertices: <({double x, double y})>[
    (x: 0.30, y: 0.70),
    (x: 0.70, y: 0.70),
    (x: 0.70, y: 0.45),
    (x: 0.50, y: 0.25),
    (x: 0.30, y: 0.45),
  ],
);

/// 箭头（内置 `arrow`）：七边形，**刻意画成横向**。
const FigureShape kArrowFixture = FigureShape(
  key: 'arrow',
  label: '箭头',
  vertices: <({double x, double y})>[
    (x: 0.20, y: 0.42),
    (x: 0.62, y: 0.42),
    (x: 0.62, y: 0.30),
    (x: 0.82, y: 0.50),
    (x: 0.62, y: 0.70),
    (x: 0.62, y: 0.58),
    (x: 0.20, y: 0.58),
  ],
);

/// 正方形（内置 `square`）：轴对齐、零微扰。
const FigureShape kSquareFixture = FigureShape(
  key: 'square',
  label: '正方形',
  vertices: <({double x, double y})>[
    (x: 0.28, y: 0.28),
    (x: 0.72, y: 0.28),
    (x: 0.72, y: 0.72),
    (x: 0.28, y: 0.72),
  ],
);

/// 一般四边形（内置 `quad_gen`）：刻意不规则，无对称轴。
const FigureShape kQuadGenFixture = FigureShape(
  key: 'quad_gen',
  label: '一般四边形',
  vertices: <({double x, double y})>[
    (x: 0.25, y: 0.30),
    (x: 0.80, y: 0.40),
    (x: 0.70, y: 0.74),
    (x: 0.30, y: 0.66),
  ],
);

/// 一份「图库」夹具：顺序与后端种子一致（house → arrow → square → quad_gen）。
///
/// 顺序有意义的用例（库里按 key 排序）照这份来；要「逆序子集」的用例请显式写成
/// `[kQuadGenFixture, kSquareFixture, kHouseFixture]`——正序子集在「被重排」与
/// 「未被重排」两种实现下渲染相同，断言没有牙齿。
const List<FigureShape> kTestLibrary = <FigureShape>[
  kHouseFixture,
  kArrowFixture,
  kSquareFixture,
  kQuadGenFixture,
];

/// 按 key 取夹具（用例里按名字引用比按下标引用稳）。
FigureShape fixtureByKey(String key) =>
    kTestLibrary.firstWhere((f) => f.key == key);
