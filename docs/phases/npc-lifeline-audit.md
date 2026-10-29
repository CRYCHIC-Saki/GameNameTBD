# NPC Lifeline 实现审计（2026-10-29）

范围：审查远端73f6f8f及本地整合ce6da40，不改动NPC/经济玩法。依据D035/D036/D041、CONTRACTS和实际调用链；下述缺口为静态代码审计，未追加人工场景复现，不把既有全量通过等同于这些边界已经验证。

## 实际已接入的功能

1. 林夏色块人物与阶段台词：开门后沿道路趋向食堂、进店隐藏镇上人物、餐厅给现有客人显示林夏名字，离店返回道路起点，面向按E对话。不是完整NPC生活模拟。
2. 正式餐厅的迎宾、传菜、收银岗位：未雇时由玩家E招呼、从传菜口端菜到客人、送客；已雇时自动。Shop仍在厨房交付时收钱，楼面动作不二次入账。
3. 单个远镇后台分店的界面：营业牌、账本/招工路径可开店、雇人、教主厨、按首个菜单项进一份原料、结算和关闭。复用旧分店规则；仅一家、不能与主店同镇、次日推进前幂等写Shop钱账，尚不计入经营等级。
4. 分店保存适配：WorldSnapshot允许既有菜单/主厨食谱携带字典快照。没有给林夏增加持久化存档。

## 结构是否复用、是否重复

| 结构 | 权责和身份 | 结论 |
|---|---|---|
| TDEconomicCustomer | 稳定resident ID、家庭、预算、七味×四段偏好、文化熟悉度、声明要求 | 原D035/D036正式画像继续使用 |
| TDMealIntent | customer_id、当次选店选菜/报价/出发区域/耐心/原因 | 原正式单餐意向，与画像分离合理 |
| Shop订单 | economic_profile/economic_intent及库存、评分、收款退款、超时 | 唯一正式订单/钱账，没有另建副本结算 |
| TDRestaurantGuest | ticket_id、位置、座位、路线、显示阶段 | 既有场景表现节点；不是第二个经济主体 |
| TDGuestVisit | 订单状态到进门/候餐/用餐/结账/离店的显示转换 | 展示规则辅助；不是第二份画像 |
| TDTownCaller | NAME=林夏、phase/cell/home/ate/meal_done | 新增独立移动对象，未绑定居民ID/家庭/偏好/意向 |
| TDPhase3Session._make_npc | npc-日期-序号、budget/home/preferences等旧字段 | 历史调试访客模型，并非本次新建，正式经济路径不以它为画像权威 |

没有发现重复class_name声明，也没有重复正式钱账。但不能说林夏复用了原NPC画像：restaurant_world._claim_caller给首个现有客人节点写caller元数据，game_shell只传名字和是否在店；未比对订单economic_profile.id。真实偏好、付款家庭和评价仍属于订单原居民，画面名字却为林夏。这是身份关联缺口，不能把“改显示名”当作完整的具名NPC消费行为。

## 待处理缺口（本轮不实施）

- 林夏没有稳定customer_id，也未持久化；TownWorld重建时重新boot，不支持自己的长期口味、家庭、日程与回访历史。
- 开店前“闲逛”实际站在起点：boot(start,start)，wander只_step(home)，已经在home立即返回。
- ate只影响台词，进店条件不检查ate/day；回家转wander后，在同一营业日可再次进店。
- 未迎宾时提前continue，跳过TIMED_OUT/CANCELLED的终止处理；已迎宾的终止订单也可能被“离店必须收银”门槛挡成pay。需要补真实场景边界用例再修复。

建议PROPOSED：以稳定customer_id给具名NPC绑定现有TDEconomicCustomer；Caller只保留移动/行程表现，通过真实opportunity_id/order_id关联餐厅显示，保持Shop唯一结算。不要再建一套偏好、钱包或选店公式。具体NPC入店频率/存档与剧本推进需后续单独确认。

## 可追溯代码

- src/town_economy/economic_customer.gd、meal_intent.gd：画像与单餐结构。
- src/town_economy/world_economy.gd：customer、选店与社会家庭预算；src/business/shop_session.gd：经济订单与付款。
- src/town/town_caller.gd：状态/移动/ate条件；town_world.gd：_boot_caller、_tick_caller、finish_call。
- src/restaurant/restaurant_world.gd：_sync_business_guests、_claim_caller、_floor_act；guest_visit.gd：phase_of。
- src/app/game_shell.gd：林夏显示同步、show_branch及楼面岗位操作。
- src/business/game_profile.gd：close_branch_books、next_day；src/town/phase3_session.gd：旧NPC工厂与分店规则；world_snapshot.gd：保存格式。

本审计由grilling要求的只读事实调查与主任务代码复核完成；未把审计建议直接写入生产规则。
