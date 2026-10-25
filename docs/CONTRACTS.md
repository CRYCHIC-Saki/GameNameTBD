# 公共契约：v3完整烹饪，兼容v1/v2历史入口

## D037 正式库存与手艺契约（2026-10-25）

- 正式库存与熟练仍由Shop拥有，存入同一槽；不接管旧调试Pantry的钱账。采购资格由已解锁且可运行菜谱主料并集＋全部运行调味定义生成，界面和事务共同检查。已持有的历史原料不删除，但不能再买未开放的主料。
- 数量继续整数千分份。配置声明供货四类、保质天数及包装单位，图标使用同一ingredient_id；一瓶/袋=1000库存单位，不臆定毫升/克。库存子版本stock_version=1、inventory_lots按ID存[{units,stored_on,expires_on}]，总量必须等于inventory；先到期先用，跨日过期记spoilage明细。旧档仅缺字段时显式迁移为当日起算的批次，不伪造历史鲜度；切配退回不延长到期。
- M6实际倒料量依赖真实按住时间和流量，以Shop剩余量裁剪并逐段幂等扣料；取消不返还已经倒出的调料。QTE和模型使用同一实际量，完成不再重复扣；缺货输入拒绝并有可见反馈。两锅共享唯一库存，不允许负数或超卖。
- set_material_sink(sink,availability)装配扣料与余量；pour_material(operation,hold,ingredient,cumulative_units)只接收当前有效工序，返回已接受累计units/remaining_units，旧回调STALE_OPERATION。inflight_materials只暴露未完成工序的实耗汇总，订单余料预算减去已倒入部分；读快照不再扣料。调料放弃算损耗，固定油/勾芡仍按已确认工序实际用量扣除。
- 熟练按稳定recipe_id累计合法手工成品的模块制作分（0–100，>=80计实际分），dish_id去重，>=400可用自动；研究、失败、取消、自动不计入。与顾客偏好满意度、每日研究灵感独立。
- mastery_version=1、mastery[recipe_id]累计分、mastery_dishes[dish_id]当天去重；mastery()返回points/threshold/automatic_available。旧档缺少时初始化为零，新字段畸形/未知子版本拒绝。自动开始缺料/未熟练/忙碌拒绝且不改状态；时间、调料、取消继续走现有会话接口。
- 自动复用固定工序和真实时钟、材料/成品规则，占用真实工位，暂停冻结，出锅仍需端盘交付；来源明确为automatic，基础操作贡献85，不能冒称手动Perfect。仍不支持营业中存档。

## D036 五镇、家庭与产权契约（2026-10-24）

- 升级补充：显式导入旧独立营业档也按其真实日期初始化社会账，只承接库存成本，不追结历史工资税息；旧文化熟悉度按别名复制到现行ID，原键保留。可选household_id出现时必须是非空字符串。钱庄窗口绑定打开时的档案，换槽后的旧按钮不准写入新槽。

- Profile包仍schema2，economy升schema2；读取旧economy1先完整校验，再保留旧非活动市场/餐馆到legacy_archive，只五个代表镇继续推进。原home记original_home，地图/研究/钱不迁走；已付货运保留原ID/来源/目的地/到货日，历史来源不再接受新订单。旧档不追扣工资、税或利息。
- 五菜系运行映射cn/chinese、eu/continental、jp/japanese、sea/southeast_asian、lat/latin_american，towns显式定义；新档routes仅home。recommend_route仍是幂等、边界、保存失败回滚的剧情接口，不附带故事正文或自动解锁菜谱。
- TDCommunitySociety持有有限家庭现金、雇主与工资应付、消费预留、公共账户和对手部门。NPC画像可携带household_id；可用消费额排除已预留菜款。预留不收钱，交付同时扣家庭余额/收菜款；小费受余额上限约束。取消释放、退款回原家庭，同令牌不能重复支付或退款。外部工资及基本生活的外部净流入/流出明确记账。
- TDCommunityBank：整数分，利率basis points/游戏日；现金中介型银行，借款从储备转出，存款为负债，不凭空发行。transact返回调用方cash_delta_cents，不直接改Shop钱包；额度、期限、逾期、流动性和重复请求先校验。玩家请求有永久幂等令牌；自动日结用每账户/动作日期游标，不逐日无限积累令牌。本金不是利润，利息分开，先息后本。
- 正利润税按当日税前经营利润计提，税前利润扣当日应计利息、实耗料、工资和运营费用；借款、归还本金、存取款、采购库存不直接增减利润。税款只有实际付款才进入公共现金账户，未付税纳入已有费用欠账。贷款到期本金在日结尽力偿付，余额不足不透支，逾期停止新增贷款。
- 建筑提供TDTownMap.commercial_parcels只读几何/挂牌范围：既有竞品商铺及商业街内三处可交易商铺。apply_commercial_occupancy先整体校验后呈现，不改住房、玩家建设区、工厂或分店。产权由economy.expansion按town/parcel稳定ID持有，version检测过时报价；重复买地不能重复扣款。
- 商业单元必须有可到达的相邻交互格；仅已划定商业区的空余地面作为内部通道，商铺实体仍挡路，不改外部道路或住房。绘制通道与碰撞一致；E在通道优先选相邻商铺，不能把整条商业街当作钱庄入口。
- 无已归属玩家地块的远镇初次经济布局用build_economic_layout按固定种子、有界32次重试排除断路商业区；同一输入重现同一几何，保存校验使用相同入口。现有主店地图不重新生成。
- TDBusinessExpansion只消费建筑给出的商铺；现金覆盖地价/建设/周转金，人员由真实家庭就业分配，工期结束才加入有限客流竞争。每镇每周至多一次投资、同owner分店上限、连续盈利和保守回本条件外置。新分店不增加家庭数或用餐机会。地图入口由Profile装配，厂商核心不改。
- money审计：家庭现金+银行储备+NPC现金+玩家现金+公共及对手部门现金，与期初余额+明确外部净流量相等；银行另验资产=存款负债+权益。营业、工资、税款、利息及日期幂等独立验证。人工连续经营仍PENDING。

## D035 世界经济契约（2026-10-24，正式槽接入）

- 独立实现位于src/town_economy，TDGameProfile装配并接入正式游戏。经济模块不直接修改建筑地图、厂商库存或Shop现金。旧独立调试世界保留原规则；不将两个世界账相加。
- TDEconomicCustomer schema1：稳定id、group_id、home_town_id、origin_id；budget_cents与hard_budget_cents整数分；taste按sour/sweet/bitter/spicy/salty/umami/numbing各四槽front/main/after/finish（0..100）；familiarity按文化ID取0..1；declared_requirements使用既有评分字段。后者才进入食品评分，其他画像仅用于消费选择。
- TDMealIntent schema1：opportunity_id、customer_id、town_id、origin_id、group_id、store_id、recipe_id、day、slot、quoted_cents、travel_minutes、expected_wait_minutes、patience_seconds、reasons。outside为显式选择，recipe_id为空，不创建虚假餐厅订单。游戏分钟与厨房秒禁止隐式混用，转换由唯一营业时间映射负责。
- TDEconomicCell schema1：id=town_id:x:y、parcel_id、zone_id、整数坐标、land_value_cents、rent_quote_cents_per_day、visibility/attractiveness 0..1、reachable及各出发区travel_minutes。报价按每格定义；实际租约属于parcel，不能对每块渲染瓦片重复扣费。TileSet只提供静态默认值。
- 三类构造复制输入；error返回明确失败原因；snapshot深拷贝，不导出活的可变模板。外部快照不授予经营交易权限。D035三项Grill已确认，费率与平衡值仍为AI-042建议。
- `TDWorldEconomy`每槽一实例。`quote(town,cart)`只读，cart单位1000=1份，返回有版本日/序号的固定报价及逐项货款/运费。`commit_quote(quote,token)`重新校验完整报价；过期STALE_QUOTE、重复DUPLICATE、库存MARKET_SOLD_OUT、运力ROUTE_CAPACITY、未开放ROUTE_LOCKED；失败不写。Profile完成Shop付款/入库与行情扣量，失败回滚两者；到货仅按arrival:shipment_id入库一次。
- `recommend_route(town_id,event_id)`为Profile剧情接口，边界调用并随当前槽保存；保存失败恢复经济快照。开放商路不解锁菜系/菜谱。`configure_cell(full_cell_snapshot)`校验完整单格记录，营业中拒绝；刷新按需缓存，不改共享地表或建筑本体。建筑线仍拥有地图，调用方在开门前重新attach_map，不直接写经济state。
- `forecast(menu)`不推进时间/随机，返回预算排除比例、expected/min/max与逐菜预期。营业每片消费有限共享机会，先选店再选菜，outside不产生订单；同family克隆菜单的总选择权重不增加。NPC原料、现金、每日座席量有限，正式玩家食品评分仍由CustomerScorer计算；取消没有虚构Food评分。
- 正式订单附带economic_profile/economic_intent和arrival_sec，耐心来自本次意向。价格锁在下单时；Food/Service/Value分别记录，未声明风味不加需求扣分；同order只记一次。人气按成交规模平滑派生，认知影响发现、声誉影响预期、品牌只作有限价格敏感度修正，不将多个指标重复相乘。
- FullKitchen.work_advanced(station_seconds)为只读事件：逐事件时钟跨度×活跃工位数；同锅并行翻炒/控温只计一份，双锅可计两份。ShopView仅在营业且未暂停时转交；非厨房画面不停止营业时钟，后台工厂时钟由GameShell统一推进，Town不再重复推进。
- Shop.settle_day先结费用/还债，随后标SETTLED。水电按开门基础+实际接待+工位秒，主店自有0租金；欠费由经济模块拥有，支付写Shop.operating_payment。收入先退菜再还债，后续手动退款资金不足则明确拒绝，不透支钱包。应急补助和正向世界收入也还欠费。
- 成本按现有领料账的移动平均记录（不是逐份销售成本会计）：采购换库存不再次扣利润，领出投料记当日投入成本；冷藏返还保留加工状态，不退款或重复认领成本。跨镇货款+运费到货后入成本池；工厂预付成本随产物入库结转。旧档无可恢复原始成本的既有工厂存货保留0历史账面成本，不伪造旧采购。
- Profile payload schema2新增economy(schema1)，存储外层校验包仍schema1。接受旧payload1并在内存显式迁移，保留现金/研究/世界/装修，不追扣过去费用、不读时覆写；未知版本拒绝。经济日期/成本游标与Shop账一致，六槽仍只允许PREPARE/SETTLED保存；临时文件/备份/校验/中断恢复复用原ProfileStore。
- 本轮原料厂调用由Town.transaction_sink交给Profile.world_transaction，工厂生产/升级扣同一正式钱包。厂商生产时长、等级、种类及建筑核心未改；NPC批发市场为背景公共供应，不将玩家厂商库存重复注入两次。

## D030 研习初版（历史；四轨输入与评分已被文末D031修正覆盖）

- ResearchCatalog拥有只读图谱、稳定HTML节点ID、菜系ID、独立chart_id/version及显式世界/营业映射；100节点并不表示100道可烹饪菜。前置为ALL，无环、重复、缺引用，未配置谱面不得扣灵感。
- ResearchSession拥有points、开放菜系、已购买资格、已解锁、最佳成绩、历史继承、奖励/推荐事件收据和挑战序号。begin(id)校验后购买一次资格并生成唯一token；input/update/finish使用真实TDCookingQTE，界面不能提交任意分数。finish仅当前挑战可执行一次，>=80解锁，低分保留资格；cancel废止token，暂停释放输入，不凭空完成。
- recommend_cuisine(event_id,cuisine_id)与grant_inspiration(event_id,amount)为剧情/升级接入口；已处理event_id幂等，冲突负载拒绝。普通高分菜按每菜每日一次奖励1点，研习不自我返奖；不把HTML加点演示按钮暴露为游戏。
- 新存档research-v1.json独立于shop-v1.json，保存本领域及世界时间摘要，不承诺全世界恢复。只读迁移已知营业ID；未来版本/坏档拒绝覆盖，临时文件/摘要/备份/明确恢复。旧解锁记录可越过祖先校验，但必须显式grandfathered；迁移不赋予其他节点免费解锁。
- 应用入口装配研习会话和旧世界/厨房；生产图谱模式禁止旧60分直接学会和Perfect绕过新节点；旧独立测试入口保留兼容模式。新档仅蛋炒饭、番茄炒蛋，读旧档保留原合法已学菜。

实际入口与语义：

- `TDApplication.enter_research()`创建原生图谱；上层装配`TDResearchSession`、`TDResearchStore`和`TDPhase3Session.attach_research`。不新增Autoload。
- `begin(id, {day,phase,spent}, available_hours)`只允许morning/evening且剩余>=1小时；点数/资格持久化成功才发STARTED及token。`input(token, action, pressed)`接收left/down/up/right；D/F/J/K或方向键通过InputMap进入。重复按住、暂停及旧token明确拒绝。
- `advance(delta)`使用可注入TDClock，实际场景以单调时间推进；`finish(token)`从真实QTE读取成绩，不接收UI分数。`attempt_completed`仅持久化成功后发一次，更新空闲时间。保存失败保留真实结果，可重试保存；取消不扣小时，不退已购买资格。
- 成绩=100×(Perfect数+0.65×Good数)/(谱面拍数+0.25×额外误按数)，80通过；仅对研习的aggregate_score生效，不改老做菜评分。读档不重新发奖励。
- `recommend_cuisine(event_id,cuisine_id)`、`grant_inspiration(event_id,amount)`：重复ID同负载返回ALREADY_APPLIED，不同负载EVENT_CONFLICT。正式剧情内容未接，无开发加点按钮。`record_cooking(day,world_recipe_id,score)`接经营真实交付/小镇实际上菜，>=80每菜每日1灵感，研习不产灵感。
- `recipe_atlas.json`是图谱和研习谱权威；C01/C03/C04厨房增量仅在`runtime_recipes.json`。营业ID为`study.egg_fried_rice`、`study.yangchun_noodles`、`study.steamed_egg`，显式映射世界ID。阳春面复用M5煮制并走现有灶台，蒸水蛋走蒸笼；金额/材料/风味参数标AI-037建议值。
- `research-v1.json`外壳版本1、payload字符串及SHA256；内容版本1含点数、菜系、资格、已学、继承、最佳分、事件收据、挑战序号、累计完成小时、世界时间摘要及±200ms偏移。无QTE现场续传。tmp写入/flush/校验，旧主档转bak再替换；显式恢复保留坏档副本，未知版本拒绝降级。
- 继续经营时只读已验证营业存档的合法解锁ID，导入研习历史；不把新实例默认五菜当旧进度。旧营业档缺新增食材键时只补零库存，不改钱和旧菜单启停；新研习解锁的菜单项才默认开启。

## D028 计划契约（PLANNED，尚未实现）

本节只约定 Phase 4-0 要落地的边界，不能当作当前运行事实。当前运行仍以 D021–D026 和后续历史条目为准。

- 食谱状态按【AI填充细节 AI-001】保存。官方节点的点亮、可研发、解锁、上菜单和熟练分开；自建食谱按 AI-006 保存，不冒充官方节点。
- 普通熟练次数按【AI填充细节 AI-002】增加。达到 6 后，普通玩家制作使用 AI-003；研发、员工自动制作和低 SAN 重演仍有各自的执行路径。
- 低 SAN 变体在整锅第一次开始加工时调用一次。输入至少包含原食谱 ID、实际食材、方法、SAN、候选映射和稳定随机上下文；输出包含执行谱、替换后食材、原显示身份和幂等 token。成品阶段只按 AI-007 的 80 分边界解析，不再抽一次随机数。
- 员工公开岗位只接受 `waiter`、`cook`、`manager`。旧 `greeter/cashier/cleaner/runner/prep/chef/manager` 按 AI-008 迁移；迁移失败不删除旧数据。
- 占时活动使用唯一 token，至少包含活动 ID、类型、开始/结束游戏时刻和来源。已有活动未结束时，新活动原子拒绝，不推进时钟。
- 市场报价输入市场大小、位置、等级、本地标签、食材和当天稳定随机；输出单价、品质、到货日、原因明细和报价 ID。提交订单引用报价 ID，重复提交不得重新报价。
- 新世界存档按【AI填充细节 AI-019】与 `user://shop-v1.json` 分开。新存档可以读取必要的旧摘要，但不回写旧档。随机业务结果按 AI-030 保存。
- Phase 4 每波合并时，先把本节对应条目改为实际字段和错误码，再写实现；没有代码和测试前保持 `PLANNED`。

## D026 入座与传菜

- 等菜和吃饭时，客人的位置是 `TDRestaurantLayout.sit_cell`，也就是这件座位家具里离落脚格最近的一格。`seated` 为真。去收银台时回到过道。
- `hold_plate` 只占用一张还在等的单，把菜放在传菜口，客人继续等，耐心继续走。`finish_plate` 才算送到。对不上的菜不会占用任何一桌。
- 玩家在传菜口按 E 端起一盘，在对应座位的落脚格按 E 放下。传菜员岗位 id 是 `runner`，推荐日薪 7。到岗后自动领取传菜口最早的一盘，走到落脚格后送达。送达质量用 `TDBranchSim.service_quality`。玩家亲手送达不调用这套修正。

## D025 餐厅客人与后厨订单

- `TDPhase3Session.floor` 是当场的客单。进门生成 `floor-N`，离开后删掉。不进入 Phase 4 存档，也不写 `user://shop-v1.json`。
- 可上菜的状态只有：阶段 `wait_serve`、正在等、已接下、还没上过、没超时、没拒绝。`TDFloorBoard.serve(dish_id, quality)` 在这些单里找序号最小的一张；`dish_id` 为空表示最早的任意一单。找不到返回 `NO_GUEST`。
- 耐心 180 秒，只在可上菜时减少。走到 0 记为超时，客人改走离开，`settle_visit` 用 `accepted=false` 和 `reason=timeout`。
- 后厨交付用 `deliver_to_guest`。菜谱 id 经 `dish_id_for_kitchen` 对回 Phase 3 的菜。对不上且不是失败菜时返回 `UNKNOWN_DISH`，不改客人。失败菜走最早一单。
- 观察不暂停。餐厅在后厨打开时继续走客人。Phase 2 的 `TDShopView` 不读这本客单。

## D024 规模维护、工资、情绪与性格

- `TDRestaurantSizes.upkeep` 是占地格子数的一半。主店记在换天账单的 `upkeep`，分店记在 `settle_branch` 的 `upkeep`。重复结算不再扣。
- 在岗员工有 `staff_profiles`：当前日薪、情绪、勤奋/懒惰、认真/马虎。`set_wage` 改的是下次以及之后的服务质量；情绪在成功发薪时按 `TDBranchSim.mood_delta` 变化。
- 出菜品质先按熟练度得到 40–96 的底分，再加上 `quality_shift`。主厨亲手出菜和分店日结用同一套。玩家亲手做菜不吃这套修正。

## D030-TOWN（原远端D030）餐厅建设区与原料厂空地

- 每个小镇地图固定生成一块 `diner_lot`（餐厅建设区，占地 12×18 或 18×12）和 8 块 `factory_lot`（原料厂空地，各 2×2）。开局不自动放置主店。
- 主店只在主小镇、未建店时，点击 `diner_lot` 后选择 `chinese`（中餐厅）或 `western`（西餐厅），再调用 `build_venue`。建成后占地是建设区的一半宽、一半高，也就是四分之一。`player_diner` 的格子可以走上去，走上去就进入餐厅。西餐厅店内风格用现有 `french`。建设不用 E。
- 8 块原料厂空地按槽位分成调料、蔬菜、肉类、水果四类，每类两块。点击空地建成 `supply_factory`。再点击已建成的厂打开生产界面。选货占三分之一，产线占三分之二。把原料拖到传送带动画上并确认数量后才开工。当前这一份的位置和还没做完的份数都画在传送带上，做完一份就写入一份 `TDSupplyBook.stock`。厂房等级等于产线数，升级加一条，每条同时一批。工时与现实流速相同，1 小时生产就是现实 1 小时，只在小镇开着且未暂停时推进。背包只读这些已入库的一级原料。单价来自供货表并随选定市场距离上浮，升级也缩短之后的新批次。
- `resize_home` 要求已建店，且新面积必须放进建设区。未建店时小镇「进入餐厅」拒绝进入主店。分店仍在非主小镇划地。

## D023 餐厅面积、雇员与分店

- 面积 id 是 small、medium、large、huge，占地 3×4、4×6、6×9、12×18。店内列数和行数是占地乘 2，并且都不小于 8。主店默认 small；D030-TOWN 起改为在餐厅建设区点击建造，不再贴中心路口自动生成。`TDTownMap.build` 的中心格仍是路。
- 岗位是迎宾、收银、保洁、备菜、主厨、店长。`employ(role, store_id)` 的 store_id 是 home 或 branch。当天从 Phase 3 现金付日薪；同一天再次雇用不再付；辞退不退。付不出当天工资的人离岗。
- 备菜和主厨都先扣 `TDPantry` 里的原料清单。没有备菜岗时玩家自己备、自己做。备菜岗和玩家不能同时备同一单；主厨和玩家不能同时做烹调。主厨只会自己卡片上的菜谱 id。品质不超过 96。
- 分店状态在 `TDPhase3Session`：town、culture、占地、菜单快照、本店库存、本店员工、按日期记下的结算。钱和 `TDRecipeBook` 跟主店共用。菜单、员工数组、分店库存不跟主店共用。
- `settle_branch` 用分店菜单第一道菜的文化、售价和参考价算客流。文化相同 +3，别的非家常文化 -2，家常 plain 在各镇相同并 +1，售价高于参考价 1.25 倍再 -2，有备菜 +1，结果夹在 0 到 8。缺店长或主厨则没有收入。不会的菜、缺货、事故分开记原因。同一 `day` 再调用返回 REPEAT，不改现金。
- 自建菜 `define_custom` 提高 version。分店菜单保存当时的 snapshot。`sync_branch_recipe` 才换成新版，并把上一版放进 history。

## D022 小镇道路、SAN 与营业时间

- 六座指定小镇仍用 `content/phase3_world.json` 的 id。地图边长 41，四条主路从中心向外随机延伸，长度随城镇种子变化。餐厅占地改由 D023 规定，中心格保持为路。广场、游乐园、小吃街、商业街的最长边至少 10。三档菜市场用 E 选定；未选定时供货清单保持原样，选定后小档和中档锁住档外材料，大档不锁。
- SAN 是 Phase 3 会话上的 0–100 整数。只有 `day_phase == morning` 时 `set_san` 生效。QTE 的 perfect/good 窗口乘 `0.6 + 0.4 · SAN/100`，只在厨房收到当天 SAN 时生效。假音符和变暗不读取经营随机数，也不改判定。
- 阴暗菜只配置番茄炒蛋 → 西红柿炒皮蛋。接受交付、SAN < 30、评分 ≥ 80、随机数 < 0.45 时解锁一次。已解锁后，普通客人约 0.03、夜宵客人约 0.08 会点这道菜。
- 工作 SAN 在收摊时按整段工作小时结算，每小时 −2。休息在换天前按剩余自由小时结算，每小时 +2。保洁跳过 30 分钟收拾，并和收银一起按每人 25% 缩短整理时间。

## D021 小镇客流与斜角餐厅

- 运行配置是 `content/phase3_world.json`，schema 1。`doc/source/towns.json` 仍只读；能对上的菜写 `source=towns.json` 和原文 id，对不上的写 `source=PROPOSED`，不回写原文。
- 货币是整数元，和 Phase 2 的分、`user://shop-v1.json` 分开。进入小镇或餐厅不写营业档。装修结果只进入 `TDPhase3Session` 的客流评价。
- 参考价、装修效果、口碑、前评价、竞争优势、三项终评和星级按 `TDEconomyMath`。装修效果 = 统一度 / 100 × 高端度。展示分夹到 0–100；选店用未夹取的竞争优势。好评是展示分 ≥ 80，差评是 < 40。总体评价 ≥ `unlock_score`（60）且玩家接下，才把菜谱 id 写入 `TDRecipeBook`。拒绝、低分和重复学习都不新增。
- 预算由 `budget_from_unit` 生成：15、50、130 的三角分布，结果至少 15。功能区人数、预算平移和外来偏好倍率来自配置，住房贡献有上限。竞品默认两家、各最多十道菜。
- 供货 `TDSupplyBook.order` 默认下一天到。`pipeline` 或 `nearby_market` 为真时当天到，并在跨天时扣维护费，钱不够就关掉。
- 备料是另一本原料账。食材身份只读 `doc/source/ingredients.json`。`content/pantry.json` 给出品类保质天数、单价和设备倍率，都标为 PROPOSED。`prep_dish` 按菜一次买齐清单；`prep_selected_ingredient` 只买当前点选的一种。钱从 Phase 3 现金扣，不够则整笔拒绝。入库日加保质天数得到 `expires_on`，跨天时 `expires_on <= 当天` 的份数清掉。换设备只影响新入库的份，不改已经放进去的。这本账不写 Phase 2 冷藏，也不改延迟进货。
- 跨天从同一本现金账扣租金、水电和按家具件数计的设备维护。迎宾、收银 `employ` 当天付工资；钱不够则拒绝到岗。已付工资不因辞退退回。下一天开始时，仍在岗的人再付一天；付不出就离岗。金额在 `expenses`，标记为 PROPOSED。
- 新学会、且原来厨房没有谱的菜，由 `TDKitchenLink.install` 挂成 `phase3.<菜谱id>`。它复用现有炒或蒸的逐拍表，并改用一份不与旧菜冲突的主料组合。评价解锁的汽锅鸡走原来的 `service.qiguoji`。旧营业档不必事先含有 `phase3.*` 菜单项。进入营业前只授予当前学会的这些菜，不改初始五菜的上架状态。
- 餐厅寻路仍是四方向过道网格。画面投影是 `TDRestaurantIsoView.project` / `pick_cell`。客人全程状态在 `TDRestaurantGuest.phase`：welcome、order、seat、wait_serve、eat、pay、leave、gone。菜单外的单停在 order，上菜停在 wait_serve，没收银员停在 pay。

## D020 实现接口与存档补充

- World.station_action(station_id, action)的action是interact/open/retrieve；旧cooking_requested与独立Phase1入口保持兼容。ShopView组合入口拥有路由，F开始后自动工序，E端成品，Q只从尚未开始加工的锅取指定实例。
- Handling.take_ingredient/put_pot/take_stored移动所有权，完整保留instance ID、切型与风味；Model.portable_data/restore_portable只接受schema1冷食包。包包含稳定ID、食材ID、份量、实际切向/质量/用时及processing_state（温度、暴露、反应、风味、口感、香气、食材历史）；非有限值、未知材料/反应和非法切向拒绝，失败前不变更。恢复不修改输入包。
- Shop状态新增progress_version=1、unlocked稳定菜谱ID列表、cold_foods实体包数组；原schema1边界档缺这三项时显式补初始五菜/空冷藏/锁定汽锅鸡，不覆盖旧档。未知progress_version返回UNSUPPORTED_VERSION。冷藏存量不重复计入整数原料库存，账本原取料消耗保持。
- context_for_ingredients(ids, complete, method)匹配主料与方法，按最早同菜订单取得要求；自由备菜由preparation_choices选谱，不依赖订单。锁定菜不参与菜单来客，初始五菜不被锁回。
- observe_finished只接受本日已出锅成品，数据库菜必需项齐全、每个实际计分工序达到外置Perfect阈值才解锁，一次写账。失败菜can_deliver/deliver匹配全队首位，0分、无收款/小费/方案，建议人气-4；重复交付不重复影响。
- QTE sequence扩展free_seasoning，复用真实按压时钟、暂停和实际加料事件；8秒自由窗口/流量0.2份每秒为PROPOSED，任意调料与用量不设对错，不发伪Perfect。已知谱仍严格定拍长按。hold_pressed/season_prompt只读真实控制器状态，早按未接受时不亮已按住。
- 自建方案仍保存工序与用量，不保存分数；新增汽锅鸡蒸制方案复用同一编译器，蒸菜备切可选，未完成关键工序不能保存。

## D020 状态所有权与操作边界

- 实体食材原身份随手/板/锅/冰箱移动；退回不还原属性、不凭空返库存。冷藏的处理食材独立于原料整数库存，料理开始后禁止逐件拆回。所有转移预检后原子提交，重复请求无效。
- 备菜按玩家切型生成谱，牛肉等所有主料可独立备菜；客人需求仍在订单和独立评分显示。锅按主料集合与炒/蒸方法识别，锁定不阻止尝试，未知组合走同一模型及QTE自动链，最终标记failed_dish。
- 配方解锁由ShopSession验证真实成品必需项及每个计分工序，幂等写入unlocked；已解锁/处理食材随日边界存档校验与恢复。旧schema1兼容缺省值不得让损坏新字段静默通过。
- 失败菜不生成可保存方案，交付只匹配全队第一位；负面反馈/人气扣除幂等，重复输入不重复结算。
- M6展示状态来自实际控制器按压/时钟；自由调味也记录真实长按量并走原库存提交，不用假成功。世界E取放、F开界面、Q取出，输入只发意图。

## D019 自动服务增量（优先于旧订单绑定契约）
- TDShopSession统一拥有实际库存、订单和经济。material_sink(token, integer_units) 在模型修改前执行整笔预检/扣料；读取、搬运、重复回调不扣料。业务向模型注入Callable，烹饪不依赖Shop类。非法、缺料、已关店和旧日请求拒绝。
- Session.select_recipe(config)仅允许无进行中工序且未加热的preparing状态；保留实际材料/切型/历史/身份，不重建成品，不修改模板。用于从自由取料识别同一菜品及装配顾客谱。
- 服务匹配按family_id（原版稳定菜谱ID），自建ID为做法与菜单项。context_for_ingredients由订单先后确定要求；没有订单时使用基础做法。交付first_order_for找最早同菜未完成订单，不靠订单会话前缀强制绑定。
- 自动路径WAITING→SERVED/TIMED_OUT/REJECTED_STOCK；不预收、不绑定锅。旧begin_order/consume_total接口已移除，旧终态订单字段仍可读取。request_profile按结构化kind/taste/fine生成独立谱；future_materials按锅实际装配的谱计算，不因顾客离开偷偷换谱。
- sync_kitchen接收真实容器快照，只缓存该营业日的独立副本；散料可用一次，锅/成品逐订单占用一次。按顺序扣除尚未完成的原料/工序需求，缺料者REJECTED_STOCK；随后新客候选过滤售罄菜。已完成调味不要求库存中再有同一份料。
- 所有玩家持有资源仍由原Handling/Session拥有；顾客超时不删除这些对象。读档仅在日边界，不保存现场；旧schema1终态订单兼容，新REJECTED_STOCK与负面反馈字段显式校验。

## Phase2营业契约 v1（D017历史；钱料与匹配已被D019覆盖）

- TDServiceCatalog显式组合只读cooking_system基础与service_content增量，产出相同TDCookingCatalog；营业active菜单独立，禁止TEST_ONLY入菜单。来源/金额/整数库存量/谱引用必须校验。
- TDShopSession拥有日期、PREPARE→OPEN→DRAINING→SETTLED、订单、库存、预留、账本、方案及经营指标；只通过方法变更，snapshot深复制。UI/厨房只发意图。订单WAITING→COOKING→SERVED或CANCELLED/TIMED_OUT；售后退款有独立幂等记录。
- 提前打烊或营业时间结束且没有未完成订单时进入 SETTLED。`day_summary()` 只读当日账本和订单：净收支、开门后营业盈亏、每一单的实收、评价和实际人气增减。结算记录原因 `early` 或 `time`。它不另记一笔钱。
- 金钱整数分，库存整数毫份（1000=1标准份），计时秒。采购/预留全量先检查再提交，库存总量不含重复副本；可用量=总量−有效预留。消费记录按食材和订单累计去重；取消仅释放未用预留。
- 订单、菜品、交易、日结、配方使用稳定ID。重复请求返回DUPLICATE/ALREADY_FINISHED，不重复扣料收退或推进日期。错单保留盘子；评分读取真实成品且不回写属性。
- 自建条目保存name/id/version与经过TDRecipeLibrary验证的食材工序plan及可复现谱，不保存成绩/随机结果。改名不变ID，制作仍执行真实QTE。
- TDShopStore仅接受PREPARE/SETTLED合法快照，版本1信封含payload文本与SHA256；临时文件→读回校验→保留备份→替换。主档损坏/未知版本不自动新建或覆盖；恢复备份须明确操作，未知版本拒绝回退。注入中断点用于真实磁盘恢复测试，测试目录隔离。
- FullKitchen增加可选station_handler与推进信号，让营业入口绑定订单并接管供料/出餐，未注入时Phase1行为不变。所有锅/菜板仍用原Session/Lane/QTE，不建立演示专用做菜路径。
- `time_boundary(maximum_sec)→正秒数≤maximum` 由营业规则注入；FullKitchen逐段推进后发 `time_advanced(seconds)`，订阅方立即处理到期清理，防止长帧晚扣料。`open_station_view/refresh_world` 是厨房公开入口；`station_names` 注入显示名，稳定功能位ID不变。Lane的 `session_namespace` 用订单ID隔离回调，`customer_override` 使用当前顾客声明需求。
- 方案只支持当前自动链：编译真实保存的切型与鼠标轨调味顺序；不能忽略不支持的工序顺序后按基础谱播放。保存字段、建议值、失败策略见 `systems/business.md`。

## D016增量契约（优先于D015冲突条目）

- 菜谱可声明 `preparation_sheets: {ingredient_id: sheet_id}`；引用须存在且为切菜谱。逐拍cut允许 `primary/rotate_left/rotate_right`，编译为 `cut_actions` 与目标刀向。旋转也是判定音符；错键、离拍旋转不改变刀向，只有成功的落刀增加 `cut_directions` 与食材细碎度。旧无cut_actions控制器只服务历史回归。
- 谱面的 `preview_beats` 为有限拍数；长按编译输出 `charge_preview_sec/start_grace_sec`。起手等待与蓄力分离：首次合法按下后提供完整目标持续时间及松手容错，始终有有限超时；暂停/失焦释放不等于出锅。
- QTE进度新增只读 `last_judgement`：递增serial、grade、reason、action、beat_index、error_sec、at_sec；重复读取不产生判定。Lane保存带显示时刻的分离反馈；UI只读取，音效只在新事件时播放。完成反馈不因qte对象释放而丢失。
- 当前本锅时表不允许M4覆盖M6；编译时检查整个鼠标占用区间。双锅M6鼠标预约通过上层入口装配，连续控制 `set_control_suspended` 保持游标、累计实际热量、排除本段稳定率分母，暂停游戏时仍全部冻结。零有效评估时长得0，不以托管冒充玩家成功。

## 当前D015自动流程（覆盖下方D014的玩家入口部分）

- 生产入口 `guided_controls=true`，会话 `pc_controls=true, document_rules=true`。普通玩家只能通过世界功能位E发送取放/开始/端盘意图，不能通过菜单指定工序、份量、回锅或拖盘。旧入口仅供独立回归。
- 唯一活动配置仍为 `content/cooking_system.json`。`pc_operations.document_sheets` 是当前权威时表；旧 `sheets/events` 留作兼容，不参与玩家自动流程。每表包含 `id,dish,bpm,groups,beats`；稳定group ID定义 `operation,parameters,label`，行的 `t` 为从1开始的有限拍号，`lanes.hand/mouse` 引用group并给出 `op,input,form`。Rest行不得含输入；同轨和控制器重叠、错误轨、未引用group、错误材料和坏QTE配置均在加载时拒绝。
- `TDBeatSheet.configure` 输出 `events`（内部编译结果），`cells`（分离的逐拍源）、`pre_roll_beats`（按需整小节预备拍）、`duration_sec`。输入目标秒数由行中t计算，不再只用t作为工序启动时间。每段键盘序列末拍Space，相邻指令串可缩短预告而不改任何输入拍点，不强迫插入Rest；持操作要求连续拍；控温hold允许鼠标中途去材料柜，期间游标继续漂移。
- `TDCookingLane.start_sheet(id)` → CONFIGURED/STARTED或BUSY/UNKNOWN_SHEET/配置错误；同一锅双轨使用独立operation_id。结束/取消后旧回调仍按会话代次拒绝。返回世界不取消时表，主菜单退出才清理；重新进厨房创建空会话。
- M6 `actual_actions` 记录实际材料；材料柜只是向现有QTE发送 `spice:<id>`。M3勾芡的外置请求可带 `ingredient_id=starch,amount`，完成时加实际淀粉并应用效果，各一次。配置模板不修改。
- `CookingModel.module_scores()` 返回分离的M1–M7分组 `{quality,weight,count}`；每组先平均，Q按模块权重一次归一，再叠加已有基础修正。`steps[].module` 是操作归属：下油/下料/翻炒/勾芡/上笼M3，精确调味M6。独立顾客评分只读快照与声明要求。
- `TDCookingLane.customer_feedback()` 返回分离的只读评价数组（含customer_name及Scorer结构化结果）。`TDGuidedCookingView`只读lane进度、快照和反馈，只发 `spice_clicked(lane_index,ingredient_id)`；不写菜品或分数。M5常驻条在世界与其他工序画面均更新。
- 输入仍经InputMap：左锅WASD、右锅方向键、共享Space；没有接收Space的M3段收到提前Space会按错误输入计。双锅合法输入不互相扣分。鼠标同一归一位置吸引两游标，目标带分开；松手立即解除，后续靠近事件可恢复弱吸引。
- 数值单位：t为拍，控制器时间为秒、窗口50/100ms，fine为[0,1]对应最多8格，游标与鼠标归一[0,1]。长帧/暂停/失焦继续沿用既有时钟与输入释放契约。建议值和冲突见D015；物理设备延迟未用合成输入代验。

## PC操作增量（D014历史基线）

- 生产会话使用 `options.pc_controls=true`，仍是同一个v3模型。`pc_operations` 与 `beat_sheets` 在唯一运行数据中校验；默认false仅用于旧入口/回归。
- `transfer_to(destination, instance_id, transfer_id)` 先完整预检，再原子转移真实实例及处理历史/品质；重复返回ALREADY_TRANSFERRED。源必须为一份可搬运备料，目标合法且不忙；失败两端不变，不再记一次供料。
- `pending_operations` 按operation_id区分温控轨与手部轨。允许heat/boil与stir/season/starch并行；其他重入返回BUSY。`cancel_operation(operation_id="")` 指定时只取消该操作，空值取消全部；旧结果不能重新提交。
- PC切菜请求为 `cut{instance_id, beats}`，结果含成功刀向 `cut_directions`；模型推导每食材形态和fine。精确调味为 `season{mode:"precise", amount}`，结果含实际材料事件和beat_index；错料照实际材料处理，非法结果原子拒绝，不用目标材料代替实际点击。
- 时间单位为秒、拍点来自统一BPM；控温坐标[0,1]。QTE过程帧持续提供游标、目标带、剩余时间、稳定占比和待按指令。输入配置按M1–M7复用五种控制器，UI不能写满意度。
- 配方库文件仍schema1，PC方案为schema2，兼容旧schema1方案；保存真实原料局部ID、顺序、切刀参数和调味次序，不保存成绩。加载后备料步骤提示实际搬运，不隔空加料。
- 所有快照为分离值；TDFullKitchen拥有手持/菜板/锅之间的编排，TDKitchenHandling拥有容器占用，CookingModel拥有菜品状态。完整字段、失败语义及建议值见systems/cooking.md。

## 历史公共入口（保留兼容，不覆盖上述PC操作）

当前权威见[systems/cooking.md](systems/cooking.md)：schema_version=3的请求/结果/快照、五QTE过程信息、双槽输入、局部方案ID、成品事件与配方库。TDRequest的operation_id在完整厨房包含session_id/代次；TDCookingQTE自身不替界面路由旧事件，Lane先验证token。下面v1/v2仅用于已有回归与旧入口，不是当前功能边界。

当前接口见 [PHASE1_INTERFACES.md](PHASE1_INTERFACES.md)。v2指数据格式，不等于旧“完整系统Phase1 v2”的范围。以下v1保留用于Phase0回归，不能当作菜品评分。

适用范围是当前跨模块验证流程。该契约没有冻结完整食材、菜谱或六维菜品格式。正式扩展必须保留来源并按版本迁移，不依赖DEV_ONLY样例的名称。

## 数据类型

| 类型 / 文件 | 必填、身份和单位 | 行为 |
|---|---|---|
| TDTemplate / content/sample_template.gd | schema_version=1、稳定id、operation=probe_hold、rate_units_per_sec、target_min/max_sec、timeout_sec、material | 配置模板Resource只读；material是嵌套Resource，metadata只允许有限JSON值 |
| TDCookingSession | session_id非空（入口分配）、generation正整数、独立模板值、revision | 运行实例；状态仅规则层拥有 |
| TDRequest | schema_version=1、session_id、generation、operation_id非空、operation、expected_revision | 操作意图；作用于本样例会话整体，具体食材目标留Phase1扩展；不携带预制分数 |
| TDInput | schema_version=1、会话/代次/操作、sequence、timestamp_sec、strength[0,1]、action=probe_hold | 连续控制输入；0松开，1键鼠按住，中间强度供控制扩展；同序号/错身份/过期时间拒绝 |
| TDFrame | schema_version=1、会话/代次/操作、单调sequence、held_sec、elapsed_sec、status | 操作结果帧，持续更新而非仅结束分数；秒数有限、非负、单调且held≤elapsed |
| TDOutcome | ok、code、message、data | 每次返回分离的值容器；ok表示该请求/帧是否被接受，COMPLETED与TIMED_OUT分别表达实际操作结局 |
| TDSnapshot | schema_version=1、scope=DEV_ONLY、会话/代次、template_id、operation_id、revision、state、work_units、held_sec、elapsed_sec、material、dish_attributes=null | to_dict返回深复制；没有真实六维结果时明确null，不用零值伪装已计算 |
| 设置JSON | schema_version=1、show_debug:boolean | 仅界面设置，不是玩家进度或现场存档 |

当前无可选操作参数。Outcome.message可为空；dish_attributes保留null明确未实现。未声明的未来字段不能被调用方假设存在。

## 方法边界与失败语义

- TDCatalog.load_file(path)/load_data(data, source) → TDOutcome；完整校验后提交，失败清空目录，不残留半加载。校验根版本/scope、ID重复、active引用、启用内容类型/单位/有限值/范围/操作枚举、嵌套元数据。候选未启用内容只检查身份索引，不当作已完成运行校验。
- TDCatalog.get_template(id) → 新TDTemplate或null；调用方拥有返回副本，不能污染目录缓存。
- TDCookingSession.begin(request) → 成功STARTED或WRONG_SESSION / UNSUPPORTED_VERSION / UNSUPPORTED_OPERATION / INVALID_ID / REVISION_MISMATCH / INVALID_STATE。拒绝不变更revision或状态。
- accept(frame) → running/completed/timed_out结果，终态发一次result_ready；错误STALE_OPERATION / STALE_FRAME / INVALID_FRAME / ALREADY_FINISHED / CANCELLED，状态不变。完成帧须至少达到样例最小目标，超时帧须到达配置时限；具体采样目标由QTE拥有并验证。
- cancel() → 首次接受，重复返回CANCELLED；终态后返回ALREADY_FINISHED；不触发成品奖励、不倒退已产生处理量。
- TDHoldProbe.input(sample) → OK / INVALID_INPUT / STALE_INPUT / PAUSED / ALREADY_FINISHED；advance()读取注入时钟返回TDFrame，终态或取消后返回null；release_input()清除强度且幂等。
- TDClock.advance(delta_sec) → bool，非法增量返回false且不改变三时钟。时钟均为相对秒；real_sec不作操作判定。
- 业务随机依赖：RefCounted对象实现unit()→[0,1]有限float。生产用TDBusinessRandom(seed:int)，测试用明确的FixedRandom。不会调用全局randf；样例只有开始时抽取目标。跨引擎版本的随机序列不承诺一致。
- TDSettingsStore.load_settings/save_settings → LOADED/SAVED或NOT_FOUND/READ_FAILED/INVALID_JSON/UNSUPPORTED_VERSION/INVALID_SETTINGS/WRITE_FAILED。坏文件、未知版本不自动覆盖；成功写先临时文件再替换并保留前一有效.bak。不宣称通用迁移或断电原子性。
- TDCustomerScorer.evaluate(snapshot, expectations) → NOT_IMPLEMENTED；这是真实接入但未实现的Phase1边界，不是评分替身或评分完成。

## 复用纪律

同一会话中的operation_id不会被重用；重开创建新session_id/generation。UI不存可写会话字典；只能使用快照副本。请求对象的身份被会话/QTE复制，不持有请求的共享可变字段。公开接口跨模块不能读下划线私有字段；集成测试可检查少量视图状态，但不能绕开操作规则。

## D018 在建增量：M6 长按（2026-10-10）
用户确认目标：围锅调料、按住才添加、实际持续时间影响风味。与 D015/D016 的 M6 单点输入冲突时以此为准；仍独占鼠标，不增加控温任务。
- 复用 sequence 控制器，以 hold_durations_sec（秒数组）与 pour_rate_per_sec（标准调料份/秒）定义每个长按音符；拍点是按下目标，时长决定松开目标。配置只读。
- actual_actions 增加 held_sec、amount（0.001 标准份精度）；判定独立评价起点和时长，实际材料/用量不能用目标材料或固定量代替。
- 暂停/失焦清除按键并冻结时钟，不自动按住；恢复后允许继续尚未结束的同一音符，已倒量保留；取消的旧操作不能再次写入菜品。
- 调味容器按下后捕获对应食材，移动鼠标不换料；窗口外松开仍释放。有限上限避免无限倒料。具体窗口/流量均为 PROPOSED。
库存和订单解绑契约待 Q1/Q2，当前不改相关依赖代码。

### D018 访客预估
TDShopSession.visitor_forecast() 返回只读值 {day,min_visitors,max_visitors,expected_visitors}，单位为人。由同一 arrival_interval_sec() 和开门1秒后的首次到店规则派生；仅供筹备展示，零随机抽取、零库存/金钱变更。旧边界存档不增加必填字段，按其日期和人气即可稳定重建。settings.forecast_uncertainty_percent 为0～50整数建议参数，默认20供旧配置兼容。

## D030 用户修正（2026-10-21，优先于旧四轨方案）

- 来源：用户四项反馈及两张截图。选中仅表示查看；未掌握的前置连线不得因选择而激活。描边必须使用空心绘制，选中/已掌握分开表示。
- 研习改用正式厨房的 TDFullKitchen / TDCookingLane / TDBeatSheet / TDGuidedCookingView；练习材料在独立会话提供，不接营业库存。配置 chart.kind=kitchen、version=2、recipe_id、primary；配置引用真实厨房逐拍表，取消原四轨生产入口。
- 研习成绩来自实际工序结果，按厨房模块权重归一。完整流程结束才结算；空打不能解锁，重复结算/取消旧令牌无效。永久资格、失败免费重试、完成一小时及80分门槛保持。历史合法解锁不撤销。
- B 打开/关闭独立屏幕覆盖层，保存底层节点与输入/处理状态，返回原场景。ASSUMPTION：主动打开书视为暂停底层游戏；研习拥有独立时钟；营业OPEN/DRAINING仅查看，不能开始研习；此前暂停则返回仍暂停。
- 未开放菜系按钮显示锁图标、禁用；switch_cuisine/select_recipe也拒绝越权浏览。剧情推荐幂等开放后才能进入。
- AC-PHASE-4-R07：选择未解锁节点不激活边；真实父子边正确、空心边框，截图及具体拓扑断言。
- AC-PHASE-4-R08：阳春面/蒸水蛋复用真实煮制/蒸制；切配/炒制仍由同一厨房接口支持，不额外造通用四轨玩法；真实键鼠完成、漏操作失败、重试与暂停不串会话。
- AC-PHASE-4-R09：游戏中B往返保留相同场景/订单/钱/食材/QTE令牌；不透传输入、不累计停留时间；营业不可研习；新解锁即时同步当前筹备菜单。
- AC-PHASE-4-R10：锁菜系不能由按钮/程序选择/搜索查看，剧情开放后可访问。

D031当前实现接口补充：begin返回token并创建未挂树的TDResearchLesson，由TrialView挂入真实Godot树后运行。input(token,action,pressed,value=1)支持原厨房primary/方向/旋转/spice:/连续温控，生产鼠标和按键经FullKitchen原路由；controller未就绪返回NOT_READY。finish从session.module_scores()读取真实模块结果，出锅流程完成后按厨房权重归一，替代D030初版四轨计分公式。lesson_mode只改变练习导航与自动衔接，不更改QTE规则；before_input保持输入前的单调时钟同步。close_research还原原对象与处理状态；失焦暂停时禁购并提示恢复，窗口关闭先还原原营业退出确认。show_san仅隐藏训练界面冗余标签，不改变真实营业SAN。
- D031的窗口、节拍和长按量唯一权威是引用厨房菜谱的document_sheets/pc_operations；recipe_atlas.settings中的旧四轨perfect_sec/good_sec/good_quality/error_weight只保留历史配置兼容，不参与新研习计分。挑战结果附lesson_version=2，历史已学与最佳成绩保留，不反向撤销进度。


## D032｜研习连续重试与选中前置连线（2026-10-22）

- 来源：用户要求暂取消研习失败后的次日限制，并整理连线、选中菜谱时点亮其前置边。仅修正D030切片。
- 研习暂与每日时间额度脱钩：begin保留available_hours参数以兼容调用，但不据此拒绝；完成无论成功失败均不新增游戏小时，不推进日期/时段。营业中只查阅限制不变；灵感购买永久资格、80分门槛不变。
- study_hours保留历史计费累计值；校验0<=study_hours<=completed_attempts<=attempt_serial，旧相等计数仍有效。旧耗时不退款、不改玩家存档；新尝试使用当前时间摘要且不加时。写入仍先校验落盘、再发布结果；重复结果/旧token拒绝。
- 失败结算提供立即免费重试，走同一begin入口与独立新会话，禁止结果按钮重复启动。暂停/取消/保存错误语义不变。
- 连线仍严格来自HTML prerequisites（ALL）；edge_active只指双方已掌握，edge_selected仅为选中节点的直接入边。金色表示当前前置关系，绿色表示掌握关系；选中不改变解锁状态。布局缓存正交路径，绕开节点及文字，不用共享大横线假装多条依赖。
- AC-PHASE-4-R11：同日零剩余时间/旧已耗尽存档，连续失败后立即重试与成功均不新增时间或重复扣灵感；真实场景结果按钮创建新token、旧回调无效；隔离读写验证旧/新计数。
- AC-PHASE-4-R12：C09仅高亮C06，C10仅高亮C07；多前置全部高亮，切换取消旧高亮；全部五菜系100节点的路径无节点/文字穿越；数据前置不变，缩放后命中与路径一致；实际Godot图形检查。
- 当前状态：R11/R12自动验收PASS；最终350/350测试和Windows导出/启动通过，证据见recipe-study.md D032。人工PENDING。


## D033 统一游戏入口（历史PLANNED，已由下节替代）
应用持有当前存档的shop/world/research/layout，切场景不重建领域对象。TDShopSession为正式单店钱/库存/订单权威，集市购买只在PREPARE/SETTLED允许；门牌开业前确认菜单。存档包按稳定槽ID、schema、revision及checksum校验；研究save_sink(candidate)使用候选完整研究数据，营业奖励只留内存至边界。换槽作废旧回调；整个包通过校验才装配。旧原型接口默认行为保持，新生产整合通过显式模式注入。AC见game-shell.md。

### D033 已实现契约（替代上面的 PLANNED）

- 身份/单位：slot-01…06为稳定槽ID；显示名可独立修改；profile schema=1、revision仅成功落盘后+1；业务钱为整数分、食材1000=1份，World的元只做转换适配。研究仍使用既有节点ID、版本和token。
- TDGameProfile公开：buy(cart)、order_remote(id)、receive_supplies()、world_transaction(callable,label)、save(candidate={})、restore(data)、next_day()、close()。at_boundary/can_leave_shop是同一PREPARE/SETTLED门禁；现货buy进一步沿用Shop的PREPARE限制。厨房保留原material_sink/实际交付接口。
- TDProfileStore公开：slots/latest/load_slot/save_slot/recover_slot；路径只能从固定ID生成。外层checksum和内部所有领域校验均通过才载入；NOT_FOUND/INTERRUPTED_SAVE/UNSUPPORTED_VERSION/SLOT_MISMATCH区别处理，损坏不会自动成为新档。
- 跨场景：Town.place_requested、Restaurant.object_requested、Kitchen.dining_requested由GameShell连接；travel切换呈现、输入和摄像机，保持同一会话。营业中去town返回SHOP_OPEN。显式模式player_mode/embedded默认为false，使旧测试与独立调试入口保留行为。
- 研究事务：save_sink收到候选，保存候选研究状态及对应业务解锁的完整包；失败不扣点、不发布解锁。营业期返回BUFFERED_UNTIL_DAY_BOUNDARY，不能写全局研究档。close使旧sink返回STALE_PROFILE；换槽取消旧试炼并断开持有的信号。
- 供货：order_remote经已有World.order_supply报价/时点和同一分钱账付款；SupplyBookcollect后receive_supply原子增加有效厨房库存并清除对应待领货。重复领取无账目或库存变化；超出容量保留供货库存，明确拒绝，不做半笔入库。
- 只读UI：右侧订单与餐厅来客投影来自同一Shop；菜单/价格、购物、退款、自建做法保存仍调用原业务方法。物件交互可打开必要清单，但常驻界面不放刷客、接拒单、伪造分数、改SAN或跨场景捷径按钮。
- 新流程的员工自动服务/分店经营未接入，保留独立debug原型和历史测试。不是删除其实现，也不对玩家收取不产生作用的雇用费用。

### D033 标题入口反馈修正（2026-10-23）
- 用户决定：开始游戏直接载入最近有效存档；没有有效存档时使用首个空槽和默认店名创建。载入存档保留选槽，另提供新建存档入口。损坏/未知版本/待恢复槽绝不按空槽覆盖；无可用槽显示明确提示。
- 标题创建/载入显示进度并防重复点击；初始化、读写错误必须在当前可见界面显示。创建、载入、旧档导入均先检查Profile初始化结果，再使用其领域对象。
- 运行食材索引固定为content/ingredient_index.json：由只读doc/source/ingredients.json显式提取分类ID/名称及食材ID/名称/sub，保留全部历史身份；不转换风味、不加入配方平衡。工具记录来源SHA256并检查派生内容一致性；原始资料继续排除出包。
- 导出验收增加实际Windows运行程序＋生产资源包的鼠标创建/读取回归，不能仅凭标题启动退出0判定存档入口可用。测试入口只注入隔离验证包，不进入发布包；写入artifacts隔离目录。

### D033餐厅移动修正
- 来源：用户报告餐厅人物在无障碍处卡住。隐藏场景不得贡献其他房间的物理阻挡。厨房墙体/人物掩码为1/2（第1/2层），餐厅为4/8（第3/4层），小镇为16/32（第5/6层）；各人物只检测自己的墙体层。层名已写入project.godot。场景切换仍保留原会话/营业时钟。
- 空地规则修正：功能分区仅限制家具放置，不再将空的迎宾/点餐/用餐地砖当墙；可通行性由边界/门面与实际blocks家具占地决定。玩家物理碰撞和顾客寻路读取同一is_walkable。家具服务落脚点仍须在movement过道，保持旧合法存档与布局约束，不把区域/家具定义重写入存档。
- 等距呈现以人物脚底为位置基准；显示落脚点和物理脚底投影一致，家具用占地底影展示阻挡范围。不修改原位图、烹饪输入或移动速度。
