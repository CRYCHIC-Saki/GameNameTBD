# D033 厨房兼容回归工作单

- 角色：cook；负责人为同一 Agent 顺序执行的厨房角色，无外部分派。
- 基线 main@a164b1c；分支 work/cook/phase-4-wave-game-shell；集成分支 integration/phase-4-wave-game-shell。
- 来源：用户 D033 正式标题菜单；AC-PHASE-4-G01/G02。
- 文件：仅 tests/integration/test_guided_kitchen.gd。旧菜单六个标签预期更新为已授权五个正式菜单；真实厨房清理、信号、重开断言全部保留。生产厨房规则没有变化。
- 验证：首轮全量中该旧菜单断言确实失败；更新后纳入统一全量。最终日志、退出码和数量统一见 docs/phases/game-shell.md。
- 状态：READY_FOR_REVIEW；仅本地集成，不提交或推送；人工试玩 PENDING。
