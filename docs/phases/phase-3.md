# Phase 3 框架：斜角餐厅与小镇客流

日期：2026-10-11。范围是用户本轮指定的餐厅、小镇、解锁、进货和 NPC，不是 `doc/agent_prompts/Phase_3.md` 里的低 SAN、成就和音量清单。那些继续延期。

技能：grilling 与 godot-gdscript-patterns 在本机都不存在，GRILL_SKILL=NOT_AVAILABLE。没有安装。等价审查后没有阻塞问题，假设记在 D021。

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
| 全量 `tools/check.ps1` | NOT_RUN | 本机 PATH 没有 pwsh |
| 人工试玩 | PENDING | 没有真人操作 |

本轮直接跑通的是上述三份测试 21 项、1897 断言，0 失败。加载检查 65 个资源是上一轮结果。画面用 RTX 4060 Laptop / OpenGL 3.3 Compatibility 截过三张，没有为这次备料重拍。

## 试玩

1. 主菜单进「走进小镇」。镜头跟着人，只能看到周围一段路。沿十字路走到餐厅、市场这些占多格的色块，或直接点「进入餐厅」。
2. 雇迎宾、雇收银，看现金减少。点「全程来客」。菜单没有的菜出现后，点「接下」或「拒绝」。
3. 客人坐下后点「认真上菜」或「马虎上菜」，看离开时的总体评价。
4. 点「客流面板」，看预算条、选店和已会菜谱。用菜价加减和「下一天」看数字变化。
5. 回小镇，在市场订货。不开加成时第二天到；买「近市」或「流水线」后当天到。点「备料」，用「按这道菜备齐」或「备这一份」入库，换设备后看同一食材的天数变长。下一天过期的原料会清掉。

## 还没接到的部分

新学会的菜使用原来的炒或蒸逐拍表，主料换成厨房里已有、且不和旧菜冲突的组合。租金、水电和工资的数字是建议值。保质天数、原料单价和设备倍率也是建议值；食材表本身没有这些数字。冻梨按苹果入库，宫保鸡丁不含花生。小镇建筑是色块。餐厅家具是程序画的菱形，不是 Kenney 图。Kenney 工具已能按关键词列出素材；下载命令会把 zip 放到指定目录，本轮只验证了检索。
