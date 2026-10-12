# Phase 3 框架：斜角餐厅与小镇客流

日期：2026-10-12。在已有餐厅和客流上增加六座小镇的随机道路、可调试 SAN、营业时段和功能区互动。成就、音量和教学打磨仍不在这次范围里。

技能：grilling 与 godot-gdscript-patterns 在本机都不存在，GRILL_SKILL=NOT_AVAILABLE。没有安装。等价审查后没有阻塞问题。上一轮假设在 D021，这一轮在 D022。

## 验收

| AC | 结果 | 证据 |
|---|---|---|
| AC-PHASE-3-001 斜角房间可走、可撞墙、可改装修 | PASS | `test_restaurant_world` 7/7；截图 `artifacts/restaurant-play.png` |
| AC-PHASE-3-002 客人走完迎宾到离开，拒绝不解锁 | PASS | `test_phase3_visit` 拒单后烤鸭仍锁定 |
| AC-PHASE-3-003 评价 ≥ 60 才学会，60 以下和拒绝都不学会 | PASS | `test_phase3_rules` 手算 97.3 分与解锁边界 |
| AC-PHASE-3-004 预算 ≥ 15，中段人数多于两端 | PASS | 800 个固定种子样本 |
| AC-PHASE-3-005 今天订货明天到，加成当天到 | PASS | 供货单测，以及小镇场景再订鸡蛋 |
| AC-PHASE-3-006 关闭城中村或小吃街会减少 NPC 池 | PASS | 小吃街 −8，城中村 −10 |
| AC-PHASE-3-007 客流面板能读出公式结果 | PASS | `session.report()` 长度和面板按钮 |
| AC-PHASE-3-008 不写旧营业档 | PASS | 来客测试前后 `user://shop-v1.json` 字节相同 |
| AC-PHASE-3-009 学会的新菜进入原厨房逐拍表 | PASS | `test_learned_dish_joins_the_kitchen_sheet` |
| AC-PHASE-3-010 租金、水电、工资从现金扣除，没钱不能雇 | PASS | `test_rent_utilities_and_wages_come_out_of_cash` |
| AC-PHASE-3-011 按菜或点选备原料，设备延长保质期 | PASS | `test_raw_ingredients_can_be_prepped_by_dish_or_by_pick` |
| AC-PHASE-3-012 六座小镇从中心长出四向道路，四个大区最长边至少 10 | PASS | `test_town_roads_grow_from_the_center_and_large_zones_fit`。D023 起主店改到中心路口旁边的空地，不再占中心格 |
| AC-PHASE-3-013 SAN 0–100，开局可改；窗口按大纲公式；评分 ≥ 80 且 SAN < 30 才可能解锁西红柿炒皮蛋 | PASS | `test_san_windows_dark_dish_hours_and_market_distance` |
| AC-PHASE-3-014 备货、收拾、整理和休息按小时改 SAN；小市场锁住牛肉，大市场可以买 | PASS | 同上 |
| AC-PHASE-3-015 假判定在距离落点两拍内消失，且不改真实判定 | PASS | `shows_fake(0, 0, 3, 0.5)` 为真，`0.9` 秒为假 |
| 全量 `tools/check.ps1` | NOT_RUN | 本机 PATH 没有 pwsh |
| 人工试玩 | PENDING | 没有真人操作 |

本轮直接跑通 `test_phase3_rules` 12/12、`test_phase3_visit` 2/2、`test_restaurant_world` 8/8，共 22 项、4217 断言，0 失败。全量 `tools/check.ps1` 仍 NOT_RUN。人工试玩 PENDING。

## 试玩

1. 主菜单进「走进小镇」。镜头跟着人，只能看到周围一段路。沿十字路走到餐厅、市场这些占多格的色块，或直接点「进入餐厅」。
2. 雇迎宾、雇收银，看现金减少。点「全程来客」。菜单没有的菜出现后，点「接下」或「拒绝」。
3. 客人坐下后点「认真上菜」或「马虎上菜」，看离开时的总体评价。
4. 点「客流面板」，看预算条、选店和已会菜谱。用菜价加减和「下一天」看数字变化。
5. 回小镇。开局用 SAN-10 / SAN+10 改 SAN，用开门和收摊按钮改营业时间，再点「开始营业」。沿路按 E 选定菜市场或功能区，点「花时间恢复」。收摊后点「去休息」。

## 还没接到的部分

新学会的菜使用原来的炒或蒸逐拍表，主料换成厨房里已有、且不和旧菜冲突的组合。租金、水电和工资的数字是建议值。保质天数、原料单价和设备倍率也是建议值；食材表本身没有这些数字。冻梨按苹果入库，宫保鸡丁不含花生。小镇建筑是色块。餐厅家具是程序画的菱形，不是 Kenney 图。Kenney 工具已能按关键词列出素材；下载命令会把 zip 放到指定目录，本轮只验证了检索。
