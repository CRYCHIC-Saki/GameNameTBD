# D033 统一存档与经营适配工作单

- 角色：economy；负责人为同一 Agent 顺序执行的经济角色。
- 基线 main@a164b1c；分支 work/economy/phase-4-wave-game-shell；集成分支 integration/phase-4-wave-game-shell。
- 来源：D033、AI-040；AC-PHASE-4-G03/G04/G05/G07。
- 实现：game_profile/profile_store 同槽经营、研究、世界、布局；shop_session 增加外部收支和到货的幂等入口；shop_view 支持注入同一营业会话和边界保存。
- 不做：新建经济公式、QTE现场存档、跨档共享研究、自动覆盖旧档。研究与烹饪规则继续复用。
- 单位：钱为整数分，1000单位为一份；World的整元在明确事务内转换。固定槽ID，错误和未来版本拒绝；临时文件读回、备份、显式恢复均校验整个包及槽ID。
- 文件：src/business/game_profile.gd、profile_store.gd、shop_session.gd、shop_view.gd、tests/unit/test_shop_profiles.gd 及对应UID。
- 公共接口由轮值集成者装配；世界快照由 town 提供，不在本角色修改。
- 验证：12项隔离存档测试；真实三日营业、研习解锁和换槽由共享场景测试完成。失败注入实际写入半个临时文件/在备份后中断，跨槽备份拒绝。最终全量证据以 docs/phases/game-shell.md 为准。
- 状态：READY_FOR_REVIEW；无提交推送，原玩家存档未操作。人工疲劳、设备手感 PENDING。

2026-10-23反馈修正：ingredient_book改为content/ingredient_index.json运行索引，全部身份与显示字段保持；tests/unit/test_economy_ingredients.gd核对源/运行索引及只读隔离。原始资料不出包，工具与导出门槛由集成者负责。所有权配置新增索引归economy，本轮13项检查通过。
