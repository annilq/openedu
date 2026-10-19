"""出题支撑模块子包（ADR-0098：自 question/ 域迁入 tasks）。

与学情工具在目录层可分：``tools/`` 顶层的 12 个工具是 agent 的工具面，本子包是
``generate_questions`` 流式 tool 的内部支撑（规格解析 / prompt 组装 / 流式翻译 /
结构化解析），只被出题链路消费，不暴露给工具面。

- ``specs``：出题规格三级来源与归一（``specs_from_context`` / ``expand_specs``）。
- ``pipeline``：prompt 组装与流式生成（``build_question_prompts`` / ``stream_question``）。
- ``translate``：引擎帧 → 协议帧翻译（``to_frames`` / ``translate_stream``）。
- ``parsers``：结构化出题解析（``QuestionSpec`` / ``SchemaQuestionParser`` / ``check_output``）。
"""
