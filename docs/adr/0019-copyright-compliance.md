# 教材版权合规决策

教材语料比对须走合法授权或公版/自编路线；自编/对外分发产品上线前，须用版权合规检测门禁验证题目未对受版权保护的教材构成实质性复制，命中即阻断发布、人工复核放行。

- **合规检测门禁**：`copyright_compliance_check.py` 扫描对外分发产物中的题目，判断是否对受保护教材构成实质性复制（原文重合度 + 结构雷同），命中退出码 1 阻断发布（决策 5）（`backend/scripts/copyright_compliance_check.py:2`）。
- **参照语料走公版/自编路线**：`protected_corpus/` 不得内置受版权教材原文，须为已授权 excerpts 或公版/自编文本，填充流程确认走公版/自编路线（见 ADR-0019）（`backend/scripts/protected_corpus/README.md:23`）。
- **对外分发必须授权**：教材（人教版等）受版权保护，自用/开发可用；做成对外分发产品上线前必须取得版权授权或改用公版/自编内容（`README.md:257`）。
- **离线自测先行**：门禁逻辑可用 `--self-test` 离线验证（识别复制 + 放过清洁内容），不依赖外部语料（`backend/scripts/copyright_compliance_check.py:215`）。
- **与 CI 门禁协同**：`compliance.yml` 把后端 `pytest` + 版权合规门禁接进发布前关卡（ADR-0019/ADR-0020）（`docs/agents/development.md:103`）。

**Considered Options**：① 放任自编内容直接上线（侵权风险，拒绝）；② 比对受保护教材、走授权或公版/自编 + 上线前门禁阻断（采用）。

**Consequences**：题目分发前经过实质性复制检测，侵权暴露面收敛到「授权/公版/自编」三选一；骨架期用 `--self-test` 验证逻辑，真实语料比对上线前启用。受保护原文绝不入库，规避脚本自身侵权。
