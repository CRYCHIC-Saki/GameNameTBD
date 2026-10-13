# 恢复当前阶段

继续当前尚未完成的 Phase，不自动进入下一阶段。
先读取 AGENTS.md、docs/DEVELOPMENT_PROTOCOL.md、docs/PROJECT_STATE.md、docs/DECISIONS.md、docs/FULL_IMPLEMENTATION_FLOW.md、docs/AI_FILLED_DETAILS.md、当前 `Phase_N.md` 及阶段记录，核对工作区和上次真实测试结果。
产品规则按 1013 会议 → 设计大纲 → 带编号 AI 填充的顺序解释。Phase 1–3 已有历史实现时只做记录中的回归或待办；不要从旧合并提示词重新执行。
当前下一阶段是 Phase 4 时，还要读取 D027、docs/phases/plan-1013.md 和 docs/COLLABORATION.md，恢复到准确波次。未获开工授权时停在方案。
从记录的下一工作单元恢复，不重做已验收工作、不重问已回答的问题。只有出现新的阻塞产品决策时才再次执行有限的 Grill Me。
按规格→实现→测试→修复→自审继续。保留未运行验证的真实状态，更新断点和阶段报告。
如果当前阶段已经交付，说明已完成及待人工验收事项，停止等待我明确指定下一阶段。
