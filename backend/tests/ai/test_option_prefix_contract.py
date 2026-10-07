"""选项标号重复：前端渲染必须剥掉模型自带的前缀（ADR-0061 §T 前端侧）。

后端 `normalize_options` **刻意不剥**前缀（docstring 明说：答案字段也带前缀，
剥离会让判题比对失配）。所以「A. 房子」这种原文会一路带到前端，由渲染层负责剥。

漏掉任何一处渲染就会显示成「A. A. 房子」—— 本文件在 Dart 侧用测试钉住这条契约。
"""
from __future__ import annotations

import pathlib
import re

import pytest


def _dart_clean_option_text() -> str:
    """从 Dart 源里读出正则字面量，避免「测试复制实现」导致同源错误测不出来。"""
    src = (
        pathlib.Path(__file__).resolve().parents[3]
        / "frontend/lib/shared/utils/option_text.dart"
    ).read_text(encoding="utf-8")
    m = re.search(r"RegExp\(r'([^']+)'\)", src)
    assert m, "option_text.dart 里没找到 RegExp 字面量（实现改了？）"
    return m.group(1)


class TestOptionPrefixStripping:
    @pytest.mark.parametrize(
        "raw",
        [
            "A. 平行四边形",
            "A、平行四边形",
            "A.平行四边形",
            "（A）平行四边形",
            "(A) 平行四边形",
            "A: 平行四边形",
            "A：平行四边形",
            "A. 2 条",
            "A．平行四边形",
        ],
    )
    def test_pattern_strips_all_common_prefixes(self, raw: str):
        pattern = re.compile(_dart_clean_option_text())
        assert pattern.sub("", raw, count=1).strip() != ""

    @pytest.mark.parametrize(
        "raw",
        [
            "房子",
            "正方形",
            "2 条",
            "三角形ABC",
            "A",
            "Apple",
        ],
    )
    def test_pattern_leaves_bare_text_untouched(self, raw: str):
        """**不能误剥正文**：像 "Apple" / "三角形ABC" 不该被削掉首字母。"""
        pattern = re.compile(_dart_clean_option_text())
        assert pattern.sub("", raw, count=1) == raw


class TestOptionRenderingSitesStripPrefix:
    """所有把选项渲染成「标号 + 正文」的地方都必须调`cleanOptionText`。"""

    #: (Dart 文件相对路径, 说明)
    SITES = {
        "frontend/lib/features/review/presentation/widgets/review_question_view.dart":
            "学生端复习",
        "frontend/lib/features/practice/presentation/widgets/practice_question_view.dart":
            "学生端练习",
        "frontend/lib/features/assistant/presentation/widgets/assistant_question_card.dart":
            "助手题卡",
        "frontend/lib/features/home/presentation/widgets/teacher/teacher_question_card.dart":
            "教师端题卡",
        "frontend/lib/features/home/presentation/widgets/teacher/teacher_task_preview_section.dart":
            "任务预览",
        # ADR-0061 §S 题库详情（我最初漏了这处 → 详情里出现「A. A. 房子」）
        "frontend/lib/features/home/presentation/widgets/teacher/bank_question_detail.dart":
            "题库详情弹窗",
        # 助手**纯文本**题卡：没有 AppOptionTile 可用，自己画标号 —— 同样必须剥前缀
        "frontend/lib/features/assistant/domain/card_payload.dart":
            "助手纯文本题卡",
    }

    @pytest.mark.parametrize("rel,label", sorted(SITES.items(), key=lambda kv: kv[1]))
    def test_site_calls_clean_option_text(self, rel: str, label: str):
        src = (
            pathlib.Path(__file__).resolve().parents[3] / rel
        ).read_text(encoding="utf-8")
        assert "cleanOptionText(" in src, (
            f"{label}（{rel}）渲染选项时没调 cleanOptionText —— "
            f"模型自带的 \"A. \" 前缀会和AppOptionTile 自己画的标号叠成「A. A. 房子」"
        )

    def test_every_manual_label_site_also_strips(self):
        """**正确的不变量**：手工按位置画标号是允许的（纯文本卡片没有
        `AppOptionTile` 可用），但**画标号的地方必须同时剥模型前缀**。

        曾经的漏网之鱼：`card_payload.dart`（助手**纯文本**题卡）画了标号却没剥 →
        显示成「A. A. 平行四边形」。所以这里按「画标号 ⊆剥前缀」来守，而不是
        禁止手工画标号（那会误伤合法用法）。
        """
        root = pathlib.Path(__file__).resolve().parents[3] / "frontend/lib"
        offenders: list[str] = []
        for p in root.rglob("*.dart"):
            text = p.read_text(encoding="utf-8")
            draws_label = "String.fromCharCode(65 +" in text or "chr(" in text
            strips = "cleanOptionText(" in text
            if draws_label and not strips:
                offenders.append(str(p.relative_to(root.parent)))
        assert not offenders, (
            "这些文件按位置画了选项标号但没剥模型自带前缀"
            f"（会显示成「A. A. 房子」）：{offenders}"
        )
