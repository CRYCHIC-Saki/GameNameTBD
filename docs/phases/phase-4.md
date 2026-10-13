# Phase 4：雇员与一家分店

状态（2026-10-13）：本文件是 10 月 12 日雇员和一家分店的验收。小组把它计入已完成的 Phase 3 可玩范围。会议要求以后只保留服务员、厨师、店长；新版 Phase 4 看 `doc/agent_prompts/Phase_4.md`、`docs/FULL_IMPLEMENTATION_FLOW.md` 和 `docs/phases/plan-1013.md`。这里已经记下的测试结果保持原样。

日期：2026-10-12。主店改到中心路口旁边，并加上占地、店内面积、岗位分工和一家分店的日结。

技能：grilling 与 godot-gdscript-patterns 在本机都不存在，GRILL_SKILL=NOT_AVAILABLE。没有安装。假设见 D023。

## 验收

| AC | 结果 | 证据 |
|---|---|---|
| AC-PHASE-4-001 不雇人也能备菜出锅；雇了备菜和主厨会扣原料、扣工资，同一工序不能两边做 | PASS | `test_player_can_work_alone_and_staff_use_real_stock` |
| AC-PHASE-4-002 四种面积的店内格子递增，生成的房间仍能从门口走到座位 | PASS | `test_sizes_grow_the_interior_and_the_floor_still_seats_a_guest` |
| AC-PHASE-4-003 非主小镇划一家分店；文化、售价会改变客流；30 天、缺店长、缺货、没钱、重复结算、读档和配方版本都按同一套规则 | PASS | `test_branch_culture_price_and_thirty_days_do_not_double_settle` |
| 全量 `tools/check.ps1` | NOT_RUN | 本机 PATH 没有 pwsh |
| 人工试玩 | PENDING | 没有真人操作 |

## 试玩

1. 走进小镇。中心格是路口。主店是旁边一块 3×4 的红色空地。
2. 选面积，点改主店面积。再进餐厅，看店内格子是否变了。
3. 雇备菜、雇主厨。备料里选一道菜并备好，点备菜岗动手，再点主厨出菜。不会的菜先点教会这道菜。
4. 换到巴黎。选面积，走到空地，点在这里划地。雇分店店长和主厨，教会当地菜，给分店备货，再结算。同一天再结算，钱不应再增加。
5. 回成都。主店员工应还在；分店员工不会变成主店员工。

## 还没做

成就、音量、教学打磨，以及第二家以上的分店。分店没有自己的实时做菜场景。

本轮 Godot 4.7.2.stable.steam.ed1daf0bf，GUT 9.7.1。`test_phase4_branch` 3/3，`test_phase3_rules` 12/12，`test_phase3_visit` 2/2，`test_restaurant_world` 8/8，共 25 项、4391 断言，0 失败。全量 `tools/check.ps1` 仍 NOT_RUN。人工试玩 PENDING。
