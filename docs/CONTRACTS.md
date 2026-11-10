# 公共契约：v3完整烹饪，兼容v1/v2历史入口

## D063 集成契约
Profile新增employees/suppliers，schema9明确兼容1–8；唯一钱账仍Shop，分店库存仍Branches，员工唯一权威EmployeeRoster，Layout的Crew是主店投影。新采购任务含来源镇/目标店/物品量/成本/真实剩余秒/幂等token，旧货单沿原路完成，不复制旧队列。经营与供应自动开关分别存档，关闭不取消已付订单。分店receive_supply原子接收带成本库存，不经过主店；有效店引用必须完整校验。
GameHUD只发action_requested，Shell唯一负责窗口/暂停/快捷键；面板调用规则方法，不改余额/库存/好感。岗位工资按日首次履职锁定归属，不靠调岗重复付/免付，低现金欠费仍计当日经营费用。新抽卡不算经营材料成本/经营净利润。

- EmployeeRoster: `draw(count,role,token)` returns paid results and exact disclosed pool probabilities; `assign(id,store)` accepts only owned IDs and existing stores. Total copies 1/3/9 imply stars; maximum 9. `payroll_for(store,day)` preserves the first duty attribution even after moves; SETTLED assignment begins the next day.
- SupplierNetwork: `quote/order(town,store,cart,token)` use integer milli-units and cents, `advance(seconds)` uses active real seconds. Completed home orders wait while OPEN/DRAINING. `set_automation` does not cancel prepaid orders; `automate` accounts for current and in-flight material needs. `legacy_lines` preserves the sum of old purchased production lines.
- Profile schema9 requires employees/suppliers; schemas1–8 explicitly migrate old workers/managers/crew/line entitlements without retroactive charges. Payment and receipt IDs must match the central ledger and target store; unknown versions, stores, items, stars or malformed records reject before mutating the live slot. The old factory data remains solely for fulfilling old queues and compatibility experiments.
- `CharacterRoster.mark_met` writes a stable string key in existing flags; relationships do not create a second NPC class or infer all characters are known. Actual visible dialogue and completed named meals establish acquaintance.


## 217cd34拉取后的兼容契约（2026-11-08）
- ShopView挂载时设Shop.crew_external=true并注入crew_status_source，关停解除所属回调，不回退旧计时器。tick_staff同时适用于现场/离店，要求真实订单、厨师、空锅与材料；每位厨师只占一个会话，不重复接玩家正在制作的菜。cook_seconds旧倒计时/模拟属性只保留独立兼容测试；正式耗时/成品由FullKitchen/Lane/BeatSheet给出。
- Restaurant.bind_dining_clock后advance_dining同时推进客人和服务员，_process只取显示位置；暂停/剧情冻结不移动、不交盘。雇用waiter抵达才hand_plate，独立runner岗位保持兼容，不新增钱物账或第二张订单。
- TownMap.economic_parcels(catalog,seed,layout,region_version)缓存键含布局版本、地域版本、种子与zones指纹，返回深副本。Profile按存档region_layout_version校验，旧/新地形可同进程迁移，不互相污染。
- ResearchStore写入前验证既有封装及业务payload，未知内部版本不能覆盖；候选临时文件写后完整校验，不通过不替换原文件。
- 仅外围facade可走到实际边墙，内部facade/家具仍阻挡；入口、装修选择模型及D059地砖轴移动保持。test_pull_merge覆盖真实出餐、统一时钟、缓存隔离及坏档保留，原场景回归不降低断言。

## D062 世界分店选址契约（2026-11-08）
- `TDPlayerBranches.quote/open_store` 只按 active_towns 校验目的镇，不检查货运 routes；现有 `TOWN_LOCKED` 对未知镇保留。其余错误码、事务令牌、分钱单位、费用和原子性不变。
- `TDBranchPanel.SiteMap extends TDTravelMapView` 共用世界插画、地图副本、坐标/镜头与五镇元数据；不是另建地图权威。`town_selected(id)` 清空旧方案，`picked([x,y,w,h])` 仅鼠标完整松手时提交意图。整数格坐标是该 town_id 的73×73地籍，水面及地图外不夹取为合法坐标。
- 选择状态不改变 `town_id/marker` 玩家标记、旅行地点、时钟或存档。界面只调用分店报价/创建；店长及菜单仍由原规则层管理。开办后重新打开视图，从同一 Profile 读取最新分店占地。
- 图形网格颜色只是提示：松手预览与最终开办均走原 `quote` 校验。不能以插画地面、颜色或点击按钮代替合法用地检查。取消、失焦、滚轮中断、切镇和隐藏不创建店铺/收费。
- `TDTravelMapView.max_zoom/minimum_view_size/heading/controls_hint/show_player` 为实例级展示设置；默认普通 M 地图行为不变。`cell_to_screen(id,cell)` 接受连续格坐标，SiteMap 反换算后取地格。无新的持久字段。

## D061-R1 地域地图契约
- `TDRegionalLayout`读取`content/towns/regions.json`，仅静态几何；`TDTownMap.region_id`关联该源。`build_economic_layout(..., region_version=2)`产生当前布局；版本1仅用于旧档验证。旅行、分店报价、经济地形、存档几何验证不可分别构造另一版地图。
- `TDKitchenPlayer.confine_to`严格为`(candidate: Vector2) -> bool`；TravelWorld校验完整短步路径、9px脚部半径、地形和真实建筑底座。轴向滑动仍由Player负责。角色PAUSABLE，地图覆盖禁止底层输入。
- Profile新增`region_layout_version: int`与`region_migration`，主schema8和主镇map_version2不变；缺省1兼容，未知版本拒绝。`TDRegionMigration.convert`不改调用方，稳定商业地块ID仅替换几何；玩家分店按稳定ID顺序保留尺寸、确定性最近合法位置。任何一店无位置则整次失败。
- 转换先过旧版完整校验，再验证候选；迁移前备份纳入槽删除/恢复文件族。备份或候选写入失败不激活新Profile；再次读取已迁移版本不再次写盘、不重新扣费。普通旅行/地图操作不保存。
- 世界图的缩放/平移/选择仅是瞬态视图状态，不改变位置、钱物、时间、剧情开放或商路。底图插画是示意；实际地块和玩家标记来源于当前Profile。

D061：TDTravelCatalog.map_for复制既有地籍及实时产权/分店，不回写Profile.world。TDTravelWorld持有单一访问地图与角色，由Shell校验港口、切换/销毁、暂停和日末。M只读，不保存当前位置。TDShopView.tick_staff只调度已雇厨师、空锅和真实已落座订单，材料/QTE/交付各沿原权威；session_id绑定锅，取消/重开拒绝旧结果。服务员承担runner，存档schema8保持。

D060：正式分店由 Profile 装配 TDPlayerBranches，独立稳定 store_id / 菜单 / 原料批次 / 店长 / 租约 / 日账，Shop 仍唯一分钱账。选址报价只读，确认时重验地形、产权、余额和已解锁菜单，开办费一次；取消无副作用。经济有限机会先比较主店、分店、NPC及不外食，选中分店才消耗其库存和家庭资金，不另生成客流。店长带班组，分店自下一日起营业；日账幂等，欠费保留。Profile schema8 同包保存并显式兼容1–7，不改变D059保存时点。旧单店快照归档后迁移，不双跑旧 settle_branch。管理选址图不代表客运已开放。

D059-R4显示修订：桌类座位处于真实seated或后半段sitting时，使用统一投影的occupied-seat图，家具绘制跳过该侧空凳；非桌类座位保持原独立坐姿。稳定ID/Shop时点不变。组合只在显示层以凳脚锚点等比定位，绝不生成第二个座位、重复确认落座或改存档。前序R3间距保留。

D059-R3：餐桌/火锅桌显示拆为独立table/stool图层，dining_stool_rect与dining_feet/dining_cushion是同一显示模型中的座位位置权威；凳子向外移动，真实Guest接近点及坐姿同步，不额外建立可持久化凳子对象。Layout家具ID/2×2格占地/容量/旋转中心不变；目录/预览/实物继续共用模型。桌前层只采样独立桌纹理的alpha，不重画凳子盖住人物。人物83.52px比例沿用R2。

D059-R2覆盖紧随其后的R1显示规则：用户明确问题是遮挡，取消强制鞋底接地和长腿图。恢复v2整幅坐姿的等比显示，家具显式提供前层遮挡多边形，仅在人物下半身相交区域重绘原纹理；原图不改，身体与下肢同一朝向/镜像。落座订单/布局/存档契约不变。

D059-R1显示修订：dining_pose_rect按素材内臀部锚点与鞋底共同定位，等比缩放，使臀部触坐垫、鞋底触家具地面；不再以固定83.52px高度只对齐臀部。依旧仅显示，不改变真实Guest落座点/时机、足迹、容量或存档。

## D059 餐厅投影输入与坐点（实现中）

D059已确认保存修订：Profile.save仍是唯一整槽持久化入口，仅主动保存（含明确保存并退出/返回）、睡觉、新档/显式导入、02:00安全收尾调用；旧档迁移只回写迁移后的载入快照。普通退出只确认丢弃，不写盘。Research候选仅校验并提交当前会话，推荐商路/等级事件确认/小屋解锁/雇佣/分店/开门与普通日结不隐式保存；同槽各领域没有独立持久化权威。安全边界和厨房整理条件、临时文件/备份失败恢复不变，槽schema7不变。设置主音量仍属独立用户偏好；研习校准属于槽快照。
TDKitchenPlayer新增独立input_transform，把输入映射为屏幕方向后归一化（保留摇杆强度）；motion_transform仍只负责屏幕到物理位移及逆变换，滑墙和步态按真实屏幕距离。餐厅装配地砖投影，其他场景默认identity。家具提供坐垫锚点，坐姿以臀部局部锚点对齐并绘制局部桌沿遮挡；属于显示契约，不修改布局ID/足迹/容量或Shop落座点单权威。保存修订见本节已确认规则。

## D058 入座点单
Shop保持唯一来访/订单权威。新增运行态ARRIVING表示已有食客意向但未正式点单，仍占到店容量/食材分配，不进入active_orders或制作/交付匹配。到店时间arrival_sec保留，confirm_seated(id,seat_id)幂等转WAITING并单独记录ordered_sec、seat_id与点单耐心；原报价/经济家庭预留不重抽、不重复预留。pending_orders包括ARRIVING/WAITING/COOKING，用于容量、超时及日结；边界存档依旧拒绝活动订单。正式Shell装配餐厅的统一时间推进/下个边界回调，不按可见性停止，不建立第二套钱物账。用户确认自动进店入座，无迎宾雇员也无需E放行；传菜与收银保持原规则。
Restaurant在可达空座之间分配唯一seat_id；无空座在不挡门/物品的区域等位，超时通过Shop取消并释放原预留。到桌后经过sit_down_sec过渡，完成才confirm_seated；同seat重调返回ALREADY_ORDERED，换seat返回SEAT_MISMATCH，取消后的迟到回调返回STALE_VISIT，缺料仍走REJECTED_STOCK。新可选终态存档字段校验类型/范围，旧边界档无需补字段，营业现场仍不保存。
Shell持有回调装配，Shop推进dining_tick(seconds)/dining_boundary(maximum)；场景关闭主动解除，角色不再额外_process计步。arrival_wait_sec是到店至点单的独立时间上限，ordered_sec只影响后厨耐心，经济等待仍从真实arrival_sec算起。TDNpcGait按真实投影位移播放，无经济随机调用；TDDinerArt缓存两身份/三衣色的只读派生纹理，正式普通人和日常对话同一appearance_id。桌椅前部脚点与家具共享绘制器对齐，不改原家具足迹或增加座位容量。

## D057-R2 整屋饰面修订（2026-11-05）

`RestaurantLayout.set_surface_finish(finish_id) -> TDOutcome`：仅接受已有floor/wall枚举，一次替换房间全部对应表面；非法ID原子失败，重复应用幂等。保留家具、区域、另一种饰面；沿用schema1逐格finish_ids存储兼容旧档。正式目录点击直接发送整屋意图，不进入旧逐格画笔。旋转显示在既有家具中心绘制，不因翻转贴图额外平移；不改变碰撞和保存的格坐标。验收见decoration-ui AC-D057-R2-001–004。

## D057-R1 拖动契约（2026-11-05）
Layout.preview_move(id,x,y)返回独立预览piece与校验结果，使用真实稳定ID排除自身旧占地，不临时从权威列表删实例。World只保留屏幕抓取偏移和目标格；松手时调用原move_piece重新校验，取消不写入布局，保存不会捕获悬浮坐标。左上叉号、右上逆时针旋转按钮为实际家具操作，rotation按-90模360；默认规则层旧rotate_piece仍保留兼容。目录移除风格/档次选择器，原style_id与房间默认风格保留。GUI、暂停、失焦、场景覆盖均终止拖拽，禁止旧松手事件提交。

## D057 装修呈现契约（IMPLEMENTED）
装修分类及卡片为只读目录，不增加家具身份或第二份布局状态。卡片/预览/实物复用同一绘制器；预览使用layout.preview_piece，只在确认放置后调用place。转向/删除仍经layout规则原子校验；右键取消或关闭选择，不再直接删除。点击实物上半部也可选中，重叠时取绘制最前的家具。UI区域必须拦截世界点击/滚轮；结束/覆盖装修清除选中弹窗及预览。旧布局schema和经济加成保持，卡片展示现有用途/风格/档次及实际装修效果变化，不发明舒适度数值。
TDDecorationPanel仅发item_chosen/category_changed/style_chosen/done；TDRestaurantWorld持有临时工具/选择，所有操作仍走原Layout。放置成功即回选择，不必先切模式才能点家具；失败保留预览及明确原因。地面/墙壁仅饰面，不变更功能区或碰撞。暂停时目录和弹出菜单停止接收输入；相机最终变换在同帧同步，预览、屏幕点选和菜单定位使用同一矩阵。现有箭头挪动/换风格能力收进家具菜单，不恢复调试常驻栏。

## D056 新档与住所契约
TDProfileStore.archive_slot(id)只接受六个固定 slot ID，只能由标题确认页发起。主档/.bak/.tmp/.preserved-*/.before-map-v2* 进入唯一 deleted/ 归档目录。先写不可变哈希清单，逐件移动，最后写清单校验值作为 committed 标记；中断在下一次读/写前回滚，源冲突或损坏清单返回 DELETE_RECOVERY_*，不覆盖。完成删除后旧备份不参与新槽恢复。槽外路径一律拒绝；运行测试只用 artifacts/。
TDGameProfile schema7，residence.schema_version=2，plot保留原稳定地块；stage=locked/invited/following/door/unlocked，reason=空/first_day/late/legacy，anchor=harbor_arrival（未解锁）或cottage_bed（解锁）。Profile拥有状态，Town通过装配的同一引用仅推进 following→door；Guide完成对话推进 invited→following，门口对话完成后调用 unlock_residence，取消不推进。unlock_residence幂等；stage非door拒绝。无第二份NPC或存档。
旧 schema1–6 恢复时只增 residence 字段，既有资格/地块保留；原地图迁移保留 residence 其他字段只替换plot。新档读取不重播CG；未解锁固定港口，解锁后固定床边，非任意位置/QTE存档。
Shop.day_opened() 与 day_settled(day) 由 Profile 同步记 Opening，关闭时断连，避免同帧开关店漏记与引用环。首次真正营业后 SETTLED 可触发落脚，零客正常算营业；从未开门的普通PREPARE不算完成。02:00沿原厨房清理/日结链触发 late 邀请，不改原 beat/tutorials，待日结床休息才跨日；收夜后未解锁只允许小镇护送、解锁后只允许小屋。


## D055 序章可重试契约
Shop.practice_supply_policy是Shell-owned StoryGuide装配的运行时Callable，返回当前允许的每原料补齐上限，教程外为空；不写入存档。Shop.replenish_practice_materials在厨房可操作时校验整个策略、统计实际库存及可回收在制品、一次记supply_delivery，重复无缺口不再发放，令牌复用持久事务序号。Shop保持唯一数量/批次/钱账；视图只在打开冰箱或有效取料意图前请求补给，不直接改账。旧存档无需schema升级，Guide载入按Opening.beat重新装配许可。厨房搬运/锅会话身份以营业日命名空间加当前持久事务序号区分每次装配，避免同日重载后从portable-1/lane-0-1重启而撞上旧扣料幂等令牌；旧令牌仍保留。
ShopView.story_cooking_check(dish,method)仅教程开火前校验主料/炒蒸方法；教程外无拦截，普通自由试菜不变。TDOpening.TRIAL_RECIPES显式列正式及既有原型身份；低分番茄炒蛋仍正常交付，不凭显示名或伪造高分放行。Guide.trial_plate_problem说明失败原因并把已有失败成品指向垃圾桶，真实E交付后清手/清锅/推进一次。
chen_door_point/bowl_point指向原食材铺正门；汤与人物提示仅soup/bowl时优先门交互，其他时期采购不变。护送首段有中门路点，暂停/远离等候/步态仍由原逻辑控制；无新增日程或居民身份。餐厅人物纯显示高度，绘制完恢复变换，不改物理大小。

## D054 接口修订（工程验收通过，人工待试玩）
TDArrivalCutscene为本地场景，sample_segment(id,seconds)仅取样AnimationPlayer可编辑轨道，读取不发世界效果；暂停/跳过/重播由原TDDialogue拥有播放进度。TDDialogueView在intro对白期间保留上一段末画面，不提前露阿铃；切段不重播跨过的音效。TDStoryGuide装配新档开篇，整场结束一次恢复港口控制，旧档不自动重播。TDHarbor稳定ID/ANCHOR不变，位置变海岸；无新的旅行许可或经济授权。CharacterRoster.safe_stop_near扩展reserved可选参数，停点避让只影响显示层，无新的经济身份。


## D053-R2 连续演出（优先于旧CG点击规则）

TDDialogue保留对话序列权威，但cg是自动时间段；tick仅消费有限非负秒，跨CG可携带剩余时间，到普通行/选择/UI即停，不把余时或长按穿透。末尾CG自动完成；skip_cg只推进当前片段，skip仍是显式整段剧情跳过且保持旧选择门槛。cg_paused只冻结呈现时间，世界仍由StoryGuide冻结；取消不发完成效果。View隐藏Gal框，整屏场景动画另有暂停/跳过本段控制，运行文本不显示原始动作说明。TDCutsceneView按外部时间取样，运动/帧/镜头/音效使用同一秒基准，无自己的游戏钟表、库存和存档。

## D053｜剧情增量契约

D053-R1：TDHarbor ID=harbor.hekou，return anchor=harbor.hekou.arrival，接近点(54,45)。facility仅layout2返回虚拟公共设施，候船棚边界(53,43,3,1)在原水域；Town四周距离判定统一纳入，Shell展示告示，禁止把它写成产权地块。`departure_request(destination,home,unlocked_passenger_routes,arrival_anchor_map,shop_open)`只返回schema1请求或INVALID_DESTINATION/SHOP_OPEN/PASSENGER_ROUTE_LOCKED/DESTINATION_NOT_READY；不扣钱、不推进日历、不直接传送、不读取货运routes。未来由剧情提供客运开放状态、场景装配者注册真实arrival anchor并在安全边界处理请求。当前生产不注册目的地，UI明确尚未通航。

Opening拥有按段剧情/教程/任务进度；Dialogue只读消费带emotion/action/cg的行，完成/取消回执经Shell路由。ShopView提供可选剧情出餐消费者，必须在真实持盘/正确菜/可交付状态下调用；剧情评价只读独立Scorer，Shop仍唯一钱物账。奖励复用原幂等令牌。导航只读地图/布局/工位，不改位置或碰撞；CG/教程冻结统一时间源，不使用额外经营时钟。Profile原story子对象追加可选v2字段，不新增独立存档。

- `TDOpening.complete_scene(scene,completed=true)`：仅当前阶段对应场景完成才转移/返回效果；取消、重发、未知场景不产生效果。`arrive_escort()`只推进follow/return，`accept_trial(dish,rating)`只接受cook阶段真实plated番茄炒蛋及非空session_id。重复已交付返回ALREADY_SERVED；错误菜WRONG_TRIAL_DISH；非法结果INVALID_SCORE，不改状态。
- `story`追加可选script_version(1/2)、hero_name(≤20字)、tracked/recipe_viewed/setup_seen布尔、tutorials和completed_scenes去重字符串数组、served_dish_id、只读assessment副本。TDGameProfile载入时先校验；未知版本/坏类型不静默丢弃。原整体schema6和现有日边界条件保持。旧cook无真实交付ID的推测分不沿用。
- `TDDialogue.add_line`增加末尾可选mood/pose/display_kind，不改变旧调用；`add_cg`以秒为单位，非帧计时。UI纯显示字幕；剧情effects仅完成回执触发。`story_replay`无scene效果键，不能重扣SAN/重领物资。
- `TDFullKitchen.tutorial_gate:Callable`为可选无参bool回调，在每次真实工序边界激活后执行。false暂停并返回已消费秒数，外层仅用该秒数推进统一世界；不得直接完成QTE或设置分数。只在首次剧情厨房启用；返回/Esc不记录教程完成，确认才记录。
- `TDShopView.story_delivery(dish)->TDOutcome`：NOT_STORY_DELIVERY才回落普通订单流程；成功清理原持盘/锅，不另发ordinary delivery，不直接结算营业额。评分复用CustomerScorer；后续剧情付款仍走原story-aling令牌。
- `TDStoryGuide`随Shell槽创建与销毁；deferred展示回调在关闭后失效。J/T/B走InputMap，文本框输入先拦截，模态/剧情/暂停不允许底层移动。寻路返回当前场景的可达点列，目标隔墙时止于最近可达外缘；汤碗选择老陈身边道路格，护送不添加实体阻挡。

## D051｜NPC位移步态与空间表现

- 新NPC步态为纯显示状态，每显示实例独有，输入实际屏幕位移、停止/冻结标记；提供facing/frame，零位移回站姿，暂停保留当前姿态，不以Time.get_ticks_msec推进、不耗经济随机。TDStoryArt.sprite(who,facing,walk_frame=-1)向后兼容，原站姿为过渡拍，新增独立步态图集只读缓存。剧情护送也提供连续显示位置。
- 餐厅project/pick与玩家motion_transform、客人步态统一使用同一投影常数，放宽格距不改layout原坐标、家具数量或存档格式；靠近物件意图仍由原Shell接收，显示/碰撞/交互用同一位置源。账本附着真实收银台，不重复造柜台。
- 新石板/建筑/住宅图集独立文件；所有原图只读。风格与光照是表现层，不改地图/道路/产权/经济随机。明确加入导出白名单及资源审计，生成描述/探针不入发布包。
- 覆盖D050素材分区：residential-houses-v2.png并非等分象限，使用实测RESIDENTIAL_REGIONS及区域内透明边界，不改变draw_residential接口。员工显示条目的actor_id由原crew稳定ID或既有岗位ID提供，标签改变不重置步态；步态不写存档。

## D050｜住宅视觉组装与居民区告示

- TDTownArt.housing_groups(map)返回独立Array[Dictionary]，条目at为Vector2i格坐标、size为1/2/3格正方形边长。按y/x稳定聚合原housing，排除实际小屋2×2和已被建筑占用的格；缓存键包含布局版本/plots/cottage，调用者修改返回值不污染缓存。该结果不写回Map，不代表经济家庭或可购住宅。
- TDEnvironmentArt.residential(index:0..3)缓存只读AtlasTexture，来源residential-houses-v1.png四等分象限；各象限只在运行时裁透明边，不修改源PNG。draw_residential按包围矩形约束宽高、底部对齐。住房余格表现为带瓦顶附房，保持原实体碰撞；庭院闭门，无新增可进入室内。
- urban_village/rich_district的已有place意图由Shell显示居民区告示，复用暂停/关闭/恢复控制；player_cottage仍走真实小屋入口。无扣钱/改产权/新增经营人口，原经济住宅距离不变。仅原道路可达位置四周按E，不要求面朝门。
- 新PNG及.import必须通过导出资源存在性检查，生成描述/开发探针/测试不得入包。Profile schema6和布局版本2不变，无新增存档迁移。

## D049｜交互外缘、常驻活动与地图装饰

- TDInteractionRange只做closest/distance/plot_bounds/facility纯几何；facing_plot保留兼容名，返回最近可达建筑/设施外缘，附只读interaction_point（世界像素）。1.1格，同距稳定ID；排除非设施住宅/总院落，短段不能穿过别栋楼或河。提示与E使用同一查询。镇上设施优先NPC闲聊；餐厅保留实际迎宾/端盘/收银优先，随后设施，再日常对话。厨房正式工位用实际台面外缘96px，历史试验工位保留88px点范围；小屋床按整床外缘。原意图信号不变。
- CharacterRoster配置schema1向后兼容新增可选activity（stand/roam，缺省roam）、radius_tiles（3–12，缺省7）、rest_sec（1–120，缺省12）；增加landmark/station区域。meal仍只代表真实经济机会的用餐资格，与活动地点分离。正式配置不把无订单角色安排到餐厅门口。
- runtime增加activity_key/dwell；仍非持久状态，不新增NPC类/钱包。按道路寻路，停点距设施外缘>1.5格，巡游目标至少相隔4格；只在切换目标/地图时寻路，地表查询/候选停点缓存。visible_people.position是格坐标插值副本，cell仍是已完成路径节点；wait只计当前步。hold冻结角色而不累积旧时间；剧情pin优先并放在安全停点，护送仍走原任务路径。实际订单继续原observe_orders/can_enter/begin_visit/finish_visit接口。
- advance(seconds,orders,minute_from=-1)支持注入起始游戏分钟：由Shell捕获原分钟并按时段边界切片；默认-1兼容固定时刻测试调用。计时不由渲染帧数决定，长段与分段空闲日程一致。02:00仍复用原收尾，不延伸日长。
- TDTownScenery缓存一张1752×1752地表（每格24px，放大2倍）和少量装饰列表；只读新图集按四象限运行时取样，不覆盖原图。装饰只放在道路外、设施交互范围外，显示底座与真实碰撞共用bounds（格坐标）。不写经济地块/产权，后续真实建筑覆盖附近时装饰自动消隐并重建碰撞；无需存档迁移。布局/道路/产权仍由原Map管理，装饰不参与NPC道路寻路或经营随机。
- 新src/world/interaction_range.gd、src/town/town_scenery.gd及assets/town/ground-materials-v3.png须显式入导出包；开发截图、生成描述和原始资料排除。

## D048｜地图版本、地形与全天用餐

- `TDPlannedTown`读取只读`content/towns/chinese_layout.json`，布局schema2、extent73；`TDTownMap.layout_version`保留旧生成器1，只为兼容验证和旧独立入口。道路、可通行、可建造分开：river/hill不可走建，bridge可走不可建；main院地可走，建筑实体仍碰撞。地形字段`terrain_type/elevation/surface_type/buildable/walkable`由坐标导出；经济覆盖不能把水面变成路。每格不分配Node/Resource，经济查询仍稀疏缓存。
- `TDWorldSnapshot.map_version`默认1，Profile schema6要求2，旧包1–5先完整按原几何验证。`TDMapMigration.convert`返回独立候选，不修改入参；按稳定ID重定位主店/小屋/分店/商业单元，保留历史地价、产权版本、库存和进度。迁移时重算位置相关路程；未映射覆盖值留在`map_migration.archived_cell_overrides`。ProfileStore复制原封包至`.before-map-v2.bak`并核对SHA256；重名异内容用摘要后缀，失败不得激活新游戏。成功备份后复用既有临时写入/校验/原子替换，不触碰真实档测试。
- `TDMealSchedule.events(count,seed,day,town)`产生按minute排序的只读副本。配置schema1，三峰高斯+少量均匀错峰，范围480–1559；时间随机独立于经济/QTE/视觉随机。总机会数仍由旧经济配置决定；`day_stats.opportunities`仍是已处理连续前缀，保留原家庭预算、选店和竞争交易。
- 正式Shop通过`day_minute_reader`注入世界钟表。开门记录`_opening_minute`，`skip_closed_before`只消化已错过的背景机会；下一事件按真实分钟换算成营业秒。`arrivals_at`给常驻角色提供该事件分钟，长帧不能用帧末分钟替代。菜单/市场预测只含剩余时段，不保证实际订单。
- FullKitchen单调时间→`ShopView.active_time_advanced`→Shell全天钟表/厂商，ShopView先结算本片营业，午夜边界再清理保存；Shell不另按帧推进。主动暂停/剧情/研习沿用同一冻结策略。手动注入测试可以关闭自动计时；真实UI/QTE仍使用原微秒计时与输入时钟。
- `facing_plot`保留方法名兼容调用，但正式行为是最近可达入口，距离不依赖朝向，等距按稳定ID。NPC对话优先时建筑高亮退让，人物显示E；工位/餐厅/小屋复用原意图信号，不在显示层改账。
- `TDEnvironmentArt`缓存只读图集区域，`TDTownArt`缓存底图，`TDDaylight.sample`仅根据注入分钟插值；不生成额外游戏时间或随机消费。导出只允许运行图像/配置，开发截图/文档不打包。


## D047 角色、日程及双布局对话

- 临时食客仍使用TDEconomicCustomer（只读画像）、TDMealIntent（单餐意向）、Shop订单与TDRestaurantGuest（可销毁显示实例）。离店释放活对象，账单快照与背景家庭账保留。取消/超时不等迎宾/收银，日结后的用餐显示秒独立于营业秒，暂停同步。
- TDCharacterRoster由Profile装配，content/characters/roster.json为只读定义；稳定character ID、家庭绑定、特性/设定/日程与关系状态分离。候选生成自己的character:ID画像和真实订单，不抢普通食客身份；预算/收付款仍属于原经济与Shop。路径仅在目标或地图变化时计算，隐藏场景继续推进，剧情位置优先；解除剧情位置后重算原目标。begin_visit/finish_visit保护进出店过程，取消订单在实际离店前不重现镇上；restore_visit_boundary不重放存档中的终态订单。
- Profile schema5追加characters schema1（clock、records），旧1–4档显式初始化，不回填历史好感；六槽使用同一ProfileStore。08:00至次日02:00、分钟单位、现实秒注入；终点强制收尾一次，日结落盘后床推进次日。未保存成功不得显示成功。不开店的午夜收尾不收开门基础费，旧真实耗料/工位费/租约与欠费继续走原账。
- TDDialogue.presentation=story/interaction，context区分story/resident/guest。剧情左右人物及active_side只影响表现，主角选项发言先于NPC回复；取消不增加日聊好感。日常回调不能经过Opening.resolve。last_completed/last_context为只读回执。


## D046 剧情厨房边界

- `TDShopSession.kitchen_available()`覆盖四个合法经营阶段；消费仍要求当前日namespace、正整数单位、整笔库存充分、唯一token。开门立即重新同步厨房分配，不重新创建CookingSession；只有经清理的隔日才重建。
- `TDShopView.checkpoint_ready()`返回KITCHEN_CLEAR或KITCHEN_BUSY及可执行提示。`TDGameProfile.kitchen_checkpoint`由shell装配，`save/next_day`检查，禁止实物丢失；研究候选返回BUFFERED_UNTIL_KITCHEN_CLEAR留在内存。不会将进行中QTE冒充可持久化数据。开门遇KITCHEN_BUSY仍可开门，保留本次实物、旧安全档并提示。
- 剧情礼包事务v2和旧v1都以run_id作身份；v2从真实菜谱需求扣除旧礼包已记账数量一次；主料单位1000，调料余量AI-054。领取失败保留欠发标记，不能把空礼包说成已发。`supplied`旧档由账本v2令牌验证/补齐。
- 经济schema2新增可选`after_hours_cost_cents`（整数分、非负）及`after_hours_seconds`（真实工位秒、非负有限数）。缺项兼容为0；SETTLED后的支出计这里，advance_day转到cost_consumed/cooking_seconds并清零。已日结books不变；无顾客时不生成订单、收入或虚假费用人数。
- `TDStoryArt`只提供只读AtlasTexture缓存；chen→ash-priest，aling→aling，方向DOWN/UP/LEFT/RIGHT。采用2026-10-29 selected archive原PNG，导出显式白名单四图与脚本。罗厄/漫画占位与正式人物图区分，未提供罗厄专属图。


> fa172f7整合保留原契约；D042-DECOR为远端原装修D042，本地D042仍指移动。AI-050-DIALOGUE指远端对话字速，AI-050仍指本地疾跑；不互相覆盖。

## D042 移动输入与碰撞契约

- world_sprint是按住式InputMap动作（左右Shift），只在controls_enabled且角色场景可处理时生效；倍率AI-050。松开恢复原walk_speed，不持久写入存档；暂停、模态界面和QTE不绕过旧禁用控制。
- 餐厅使用独立绘制project核对屏幕位移。非等比例投影下，碰撞滑动必须受本物理步的屏幕位移预算约束；使用引擎真实扫掠碰撞，不先穿过再回拉位置。保留碰撞形状、基准速度和D040实际位移动画。

## D045 食谱处理说明（2026-10-28）

- `TDPrepGuide` 只读烹饪目录、研习图谱和进货规则。不写存档，不改 `pass_score`、灵感、前置或菜系锁。
- 食谱详情和灶台食材页调用同一入口。有备菜谱时显示该谱的切配说明；细碎范围用现有片、块、条、丁。没有备菜谱时才按原料类别说明。
- 解锁句子对应现有状态：UNLOCKED、AVAILABLE、RESEARCHABLE、POINTS_SHORT、PREREQUISITES、CHART_PENDING、STORY_LOCKED。购买句子对应现有规则：调料始终可买，主料跟随已掌握菜谱。

## D044 第一日剧本（2026-10-28）

- `TDOpening` 的 `beat` 为 arrive、follow、soup、cook、founded、done。缺记录或无法识别的记录保持未开始，不把旧档拉回第一章。Profile schema 仍是 4。`story` 只在章节已经开始时写入快照。
- 新档在 `create_game` 存档前 `begin()`。到达时阿铃站在离主店门口至少三格的道路上。报上名字后她沿路走向食材铺，不占门口那一格。进入 cook 之后，她改站到主店旁。罗厄没有实体。三人都暂时画成主人公的厨师图。
- `talk` 可以带 `page` 分格，只显示文字漫画。`resolve` 在尝羹或拒绝时给出一次 `grant`。金额和库存都走 Shop：试做用 `receive_supply`，阿铃的付款仍是 `service.tomato_egg` 的 `reference_cents`。港口对话还要求菜单开着、售价等于参考价、下一份库存够，并且这一天曾经从 OPEN 进入 SETTLED。
- 成立讨伐军时欠阿铃一笔账。金额是 `service.tomato_egg` 的 `reference_cents`。只在 PREPARE 或 SETTLED 用 `world_adjustment` 入账，令牌按本局 `run_id` 只成功一次。入账失败不退回剧情。完成度由离开厨房时的番茄炒蛋快照写入，状态须是 plated、delivered 或 completed。`good` 为完成度 >= 80。
- 对话立绘里，阿铃、老陈、罗厄和漫画分格使用主人公的厨师图。林夏和客人的对话、订单、迎宾、传菜、收银都不改。

## D043 人物对话（2026-10-28）

- `TDDialogue` 保存句子和选项。短按先显示完当前句，再进入下一句。按住超过 0.32 秒后每 0.07 秒快进，遇到选项停止。`skip` 跳到下一个选项；后面没有选项就结束。`pick` 只记录选项并显示对应的下一句。
- 对话框盖住画面并压暗背景。左键由对话框接收。跳过按钮在选项出现时停用。立绘按 `linxia` 或 `guest` 用色块绘制。
- 林夏的 `conversation()` 和客人的 `TDGuestVisit.conversation` 不修改阶段、订单或现金。正式店里，迎宾、传菜、收银这些 E 动作仍先于对话。

## D042-DECOR 装修预览、饰面和功能区（2026-10-27）

- 非门面家具可放在 movement、reception、ordering、dining 任一地板上。门面家具仍只放墙上。落脚点必须是地板，且不压在这件家具自己身上。墙上放置仍返回 `WRONG_ZONE`。
- `facility_zone(x, y)` 读盖住该格的家具区域；空地返回空字符串。客人入座仍看 `seat_use`，不看地板颜色。
- `set_finish` 接受地板 `wood` `tile` `stone` `carpet` 和墙纸 `paper` `stripe` `floral` `brick`。刷错位置返回 `BAD_FINISH`。布局 schema 仍是 1。只有刷过的格子才写入 `finish_ids`；缺这个键表示全空。`decor_of` 不读取饰面。
- 布置中滚轮改放置朝向；已选中家具时滚轮调用 `rotate_piece_by`。放置或刷饰面时右键回到选择，不调用拆除。

## D041 镇上客人、分店和三个店内岗位（2026-10-27）

- 林夏只存在于正式小镇画面。`phase` 为 wander、to_diner、dining、home。dining 时餐厅把最早一单标成她的名字。离开或 `finish_call` 后她回到镇上。不写第二本客人账，不改 Shop 订单状态机。
- `floor_service` 为真时，迎宾、传菜、收银读 `TDPhase3Session.staff`。未雇则分别卡住入座、开吃、离店，直到玩家对客人或传菜口按 E。已雇则这三步自动发生。画面动作不调用第二次 `deliver`。工资走 `world_transaction`，日薪仍是迎宾 8、收银 8、传菜 7。
- 分店用 `open_branch_in_town` 在非主店小镇划地，然后回到主店地图。`buy_branch_portion` 按菜谱 `ingredient_cost` 扣一份。`close_branch_books` 在日结进下一天时调用一次；`branch_settled` 已有当天则不再加减现金。保存仍走世界快照：菜单项可以是带 `dish_id`、`snapshot`、`history` 的字典，主厨菜可以是带 `dish_id`、`version`、`proficiency` 的字典。
- 分店现金差额记为 Shop 的 `world_adjustment`，标签「分店日结」或「开分店」。等级经验不读取这笔分店利润。

## D040 主角视觉契约

- R2计步的屏幕还原使用motion_transform.affine_inverse().basis_xform(实际位移)，不能对非正交投影使用basis_xform_inv。测试/图形探针从餐厅绘制project独立量距离；相位按真实屏幕140/224距离推进。R1倍率保留，纠正其旧验证度量，物理移动参数不变。

- R1：sprite_height只决定视觉大小，walk_cycle_distance决定一循环的位移长度，vertical_stride_multiplier仅调上下朝向步频；默认140/1.0。内部相位归一化，转向连续；放大角色不能隐式改变步频或物理速度。厨房100、小镇72、餐厅/小屋70；小镇步态96、餐厅前后224，其余140。

- TDChefArt.texture(facing, walk_frame=-1)返回共享只读AtlasTexture：-1为用户原站姿，0–3为该方向行走帧；非法朝向回向下，帧索引约束在合法区间。缓存只保存视觉资源，调用者不得修改atlas/region。
- TDKitchenPlayer持有每实例的walk_frame/距离，animation_texture()只读当前贴图。move_and_slide/道路限制完成后的位移经motion_transform逆基变换为屏幕距离，才推进循环；不改世界位置/速度/碰撞或face/faces_target规则。
- 餐厅sync读取玩家的facing/walk_frame，自己只负责投影与遮挡排序；普通Sprite2D与餐厅使用同一底部脚点、等比例帧。静态读取不会推进动画，NPC/雇员仍使用原美术。
- 站姿/行走图为运行资源，设计原稿、生成提示和测试探针不出包；没有新增存档字段或Autoload。

## D040-VISIT 正式客人、装修选店与订单阶段（2026-10-27）

> 整合来源：origin/main的732d144；远端原编号D040 / AI-048，保留原意，以VISIT后缀与主角记录消歧。

- Shop 订单仍是收款、退款、超时、缺料和评价的唯一权威。餐厅里的进门、等菜、用餐、结账、离开只读取订单状态，不另记一笔账。
- 用餐固定看店铺时钟 6 秒，结账收尾 2.2 秒，之后离店。暂停时两边一起停。满座时新订单留在门口等位，不穿家具。
- 整合兼容：正式Shop订单的pay阶段仍在座位显示；旧service_active访客的pay阶段包含走到收银台的路径，不能在每次更新时强制放回椅子。AC-MERGE-VISIT-001要求旧流程完成离店并产生评价，AC-MERGE-VISIT-002要求正式pay仍保持就座且不二次记账。
- `interior_effect < 0` 时 `decor_match` 仍是区位吸引力。正式入口写入当前布局效果。效果 30 的加减量为 0；偏离按 `/80` 计算，夹在 ±0.25。该值不进存档。选店说明追加在原有理由之后，不改随机序列。
- 竞品告示显示装修效果和当日“机会 / 本店 / 竞品 / 在家”。功能区色块不改变原有人数、预算和 SAN 恢复。

## D039 移动与住所契约

- Player.facing为屏幕四向，静止保留；motion_transform仅把屏幕归一向量转换到房间物理坐标。餐厅真实move_and_slide＋四边围界，门只由交互切场景。faces_target使用屏幕投影后的目标方向；小镇E选正前方相邻格，鼠标仅选中，操作必须靠近面向。
- Profile整包schema4增加residence={schema_version:1,anchor:"cottage_bed",plot:{id,x,y,w,h,approach_x,approach_y}}；初次create显式店外，load按床边锚点。v1–v3显式选固定空置住宅迁移，保留所有旧领域；未知版本/越权占地拒绝。小屋独立场景不掌管日期或钱。
- 床在PREPARE只保存，SETTLED先保存日结再推进及保存次日，OPEN/DRAINING拒绝；重复回调绑定槽/日期，不能连续跳天。现有其他边界保存继续保留，恢复位置统一床边。
- BGM由入口装配，无Autoload；休闲/营业流退让给实际可见烹饪/研习的120BPM同步流。隐藏同步流静音但保留时钟相位，暂停同时冻结；原命中反馈只对可见操作发声，不改变判定公式。

## D038 经营等级契约（2026-10-26）

- TDLevelProgression是独立RefCounted规则，配置content/brand/progression.json；不拥有钱/库存/灵感钱包。日输入{day,stores:[{store_id,scale_milli,profit_cents,popularity_before,popularity_after,awareness_before,awareness_after}]}，货币分、规模1000=标准店、指标0–100。相同ID拒绝；整体净利润先汇总再取正/规模归一，指标按规模加权日净变化后取正；一天只映射一次，最高100XP。
- 当前正式适配只读主店WorldEconomy的税后profit_cents、人气和awareness，规模1000。日基准在等级快照保存；不读菜品名气、菜单和现金余额差，不计NPC/旧分店。未来正式分店必须一次提交全体真实经营店，不逐店调用经验结算。
- Shop.day_settled在所有经营账完成后发出。Profile用等级/研究候选先校验再一起提交内存，奖励经隔离Research.grant_inspiration验证；不递归调用save_sink。单包schema3必含progression；schema1/2显式从已结算日迁移为Lv1/0XP，无历史补发。保存失败保留完整内存候选，磁盘按已有临时/备份恢复，不出现一半奖励落盘。
- settle重复当前日相同输入返回ALREADY_APPLIED，冲突返回DAY_CONFLICT；旧日拒绝，跳日拒绝；snapshot和展示只读。日记录保留28条，等级奖励和事件按稳定level ID保存；负指标不扣XP。等级最高50（可调建议），满级不再加经验。
- 每级奖励灵感由Profile调用既有grant_inspiration，ID为level:v1:<等级>:inspiration；重复不再给。levels/rewards数据自动到账，非手动领点。pending_events与acknowledge_level_event用于至少一次投递/显式确认；消费方按事件ID幂等，不能把瞬时信号视为可靠剧情执行。feature/furniture/story/event通过配置hook target_id与entitlement查询接入；本轮不配置虚构功能或剧情。
- 旧AI-005的每升一级5点、AI-025的品牌终局5级不是本次硬规则；本次独立经营等级不改变已有0–1品牌信任和未来终局。

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

## D038-CREW 餐厅雇佣实验（远端原D038）

- 合并工资与经营等级：经营税前利润扣除上次日结标记之后发生的实际员工工资；日结后、次日开业前雇佣的工资计入下一营业日。日结账记录`wages_cents`，重复日结不重复扣减；存档前后的账本顺序为唯一依据。此归属是集成时的可调整假设，不追改旧日结。

- 名册在 `TDRestaurantCrew`。岗位 id 只有 `cook` 和 `waiter`。加成 `faster_service`、`secondary`、`tip` 各自最多生效一次。
- 布局存档在原 `staff` 迎宾/收银记录之外增加可选 `crew`。缺省表示无人。格式和经验见下面两条。
- `faster_service` 只乘新订单的可等待秒数，不改 QTE 窗口。`secondary` 在评分前复制菜品属性并拉近客人要求，不改原菜完成度。`tip` 在家庭付款前乘小费。工资记 `wage`，现金不足不入职。
- 经验记在布局 `crew`。成功送达且不是失败菜时，每名在岗雇员经验 +1。等级是 `1 + xp / 4`，最高 5。加成幅度是满级幅度乘以等级/5。满级幅度仍是等待 +25%、二级参数 20%、小费 +25%。同一种加成取在岗者中的较高等级。
- `crew` 可以是旧的 id 字符串，表示在岗且经验为 0。也可以是对象：`id`、`xp`（0 到 16）、可选 `hired`。`hired` 缺省为 true；`hired` 为 false 只保留经验，不视为在岗。存档 JSON 读回的整数可能是没有小数的数，仍算合法经验；带小数、超出 0 到 16、未知 id、重复 id 或超员都拒绝读档。
- 招工处只雇厨师和服务员，不提供迎宾、传菜、收银。正式做菜走文首的真实灶台，不并行旧倒计时。后厨里 `crew_work` 为「做菜」的厨师按取料、切菜、上灶、出餐的顺序各走一次，走到后站定；热锅、翻炒、调味、勾芡共用灶前站位，不左右晃，也不退回已经做过的工序。没有这单、缺料或玩家占着这道时站回灶前。餐厅画面不画厨师，也不画迎宾、收银或传菜。正式餐厅里走动的员工只有服务员。南墙后厨门左侧是出餐口。菜出餐后先放在出餐口，服务员只负责上菜：沿可走的过道走到座位外侧的空格，不穿过桌椅，放下菜后走回门口。做菜期间不离岗。没雇服务员时由玩家到出餐口端菜。厨房里只画厨师。名字牌带当前等级。走动速度和站点间隔见 AI-072。正式餐厅玩家不能走出店外。画出的北墙、西墙和房间外沿挡住人；门前和原来店门旁边的空地不再是整格空气墙。客人寻路仍只走可走格，店门格可以站。

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
- 8 块原料厂空地按槽位分成调料、蔬菜、肉类、水果四类，每类两块。四类使用 `assets/town/supply-factories-v1.png` 的四张不同厂房图；空地是同一张图的淡色，建成后恢复本色。靠近空地按 E 建成 `supply_factory`，鼠标点击不建设、也不打开。建成只改这一块的种类和名字，不重算道路、房屋或商业地块，玩家留在原地。再靠近已建成的厂按 E 打开生产界面。选货占三分之一，产线占三分之二。把原料拖到传送带动画上并确认数量后才开工。当前这一份的位置和还没做完的份数都画在传送带上，做完一份就写入一份 `TDSupplyBook.stock`。厂房等级等于产线数，升级加一条，每条同时一批。工时与现实流速相同，1 小时生产就是现实 1 小时，只在小镇开着且未暂停时推进。背包只读这些已入库的一级原料。单价来自供货表并随选定市场距离上浮，升级也缩短之后的新批次。
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

### D063-R1 员工抽取修订契约
EmployeeRoster内部schema2明确接受并迁移schema1，Profile9不变。生成身份employee.v1.<surname_id>.<given_id>，组件ID固定、显示名字和数组排序不作持久身份。给定组件确定岗位/能力原型；原18模板只作为能力原型及历史员工兼容。保存只存实际获得的ID/份数/XP/派驻，不展开组合池。
每次独立抽drawn_stars；copy_value=1/3/9，合并copies=min(9,old+value)，最终stars仍用3/9阈值。结果同时含抽取星级和合并后星级；已满星不再抽取，溢出进度不补发新员工或金钱。保留新伙伴保底，但不修改星级概率。原资金事务、执勤工资冻结和主动保存不变。旧已拥有且未满星员工仍以原身份参与同名抽取，满星后移出。

## D064 固定招聘契约
Roster内部schema3读取1/2。config.fixed_employees是新签约权威，每人稳定ID/固定星级/四维/特性/日薪/签约费/来源镇/简介；头像从稳定ID映射到既有6种通用形象；旧templates/name_generator只读兼容已有员工。market_rows(town,role)返回只读候选快照；sign_employee(id,token,offer_key)检查当批候选及有效期、仓库唯一、边界与真实资金，失败不变更，成功记contracts[id]={token,day,fee_cents}并入仓库，绝不自动派驻。draw旧入口返回RECRUITMENT_REPLACED。
Profile验证签约与Shop真实负支出金额/日期/付款主体/唯一token一致。旧draw seen保留作账证，不重新扣费。签约不计工资，assign才按已有首次执勤规则冻结工资；SETTLED变更及未来开业店次日/开业日生效。查看/换页/托管不签约、不落盘。

## D065 统一店铺管理接口（2026-11-09，已实现）
列表稳定主店ID player_diner 加既有player-branch:N；UI导航只读。Profile只新增可选布尔main_management_auto（缺省false），schema9不变，错误类型拒绝；不把主店插入branches.stores。Profile.main_menu_rows给主店已掌握菜谱视图，Shop.configure_menu批量全验证后一次替换菜单、只允许PREPARE/SETTLED；失败不部分改价格/开关。set_main_management须已派店长，筹备自动选择菜单并补闲置厨服；工资沿EmployeeRoster，无新制作或结算计时器。关闭后配置保留，不撤现任员工。
店铺详情页以id路由：主店菜单→Shop，分店菜单/预算/暂停→Branches，员工→EmployeeRoster，供货开关→Suppliers，账本→既有Commerce或分店books。动作成功只改槽内存，禁止UI写盘。

## D066 控制台契约（先于实现登记）
DebugCommands按调用参数取得当前Shell，不持有旧Profile。纯文本tokenizer支持双/单引号，无eval/脚本/任意存档字段写入。未知命令、坏数量/歧义名先拒绝，无部分动作。事务令牌带debug命名与run/serial唯一值，钱物仍走Shop/Branches，签约必须当前候选并真实付款。
Research新增显式debug_unlock事件：仅含kind与recipe稳定ID，校验该菜存在且已解锁、菜系开放；调试授予同时补祖先和菜系，不改best/attempts/license，不假装研习通过。新可选事件种类在原schema1下校验，旧档不变，未知/坏事件拒绝。其余系统仍经changed同步正式研究。
控制台不直接设置任务beat或剧情奖励，不模拟整天运行；time set只改合法筹备/日结钟表并同步NPC日程，原保存纪律保持。所有修改有当前槽反馈，只有显式save写盘。


## D067 分店生命周期（2026-11-09）
Branches内部schema2，Profile仍9；schema1先验证再按Shop真实开办流水补construction。新开办保存construction{schema_version:1,kind:paid,token,paid_cents,paid_day,ready_day}，ready_day==start_day；旧world_adjustment付款为legacy_paid；缺付款为unverified，不能形成可进店/营业地块，原记录与供货引用保留。一个付款token只能对应一个店。只有明确确认付款才创建或修复记录，UI框选纯本地。
施工以日期跨度计算，默认1日；built是只读查询，不通过UI或debug time set修改。店长由Roster唯一授权，正式新建不强制提前任命，完工后仍须分配店长和厨服。员工可提前派驻但施工不计薪；管理托管不能自动补出首位店长。施工/未核对禁止营业销售，完工无班组不收开门水电，日租按建成日起计。
分店巡视只绑定profile+store_id，复用餐厅绘制/厨房场景和原玩家移动；不复制Shop/World会话，不接主店订单/库存写操作，查看内容由当前分店查询。Shell管理室内生命周期、原镇返回、暂停与02:00回家。保存不记录临时巡视场景，仍按床边/港口锚点恢复。

D067补充：unverified原记录保留在legacy.unverified_archive；整槽产权重建排除这些不占地记录，真实已付/施工店铺仍严格互斥。供应可在明确开启后为施工店提前下单备货，禁止为unverified新增采购；旧已付收货仍引用同一店ID。readiness与销售/费用均检查建成；旧带薪职责不补退款。


## 2026-11-09 整合3719c13：厨师真实工序与当前员工权威
市场market_ids/market_sells允许全部实际上架原料，supplier catalogue仍读purchase_ids按解锁过滤。餐厅只有当前仓库派驻服务员负责出餐口取菜/过道送餐及原收银兼岗，不恢复旧直接雇佣按钮；工序由ShopView实际CookingLane提供，crew_external保持true。新增只读cook_job_id(person_id)返回当前真实session_id，未知/已关闭返回空串；KitchenWorld只按身份切换清理显示工位，不能清除菜品或瞬移角色。ShopView.close按自身绑定身份释放状态/工序/会话三个回调，防切槽旧回调；分店巡视不绑定主店订单。
验收AC-SYNC-3719-001保留远端取餐路径/厨师动作与本地仓库、日期、施工；002连续两次真实制作复位显示工位，不并行旧做菜计时器；003市场与供应过滤分离，关闭回调失效；004原资料字节保留，导入加载及全量检查真实记录，未验证项不得判通过。

整合补充：floor_service=false仅供原自动楼面表现兼容，正式场景true仍须真实端菜；员工仓库外部投影为空不能回退旧雇工。当前题页测试只计可见按钮且显式校验HUD隐藏；移动按D059地砖轴，研究仅缓存在槽内存。schema5旧地图测试必须去除后来的region标记并以旧几何生成，跨两次地图升级的备份为before-region-v2；施工测试先真实付款，不虚构默认店长。上述为测试样本校正，不放宽生产存档校验。AC-SYNC-3719-001至004工程通过；证据见game-shell最新整合报告，人工试玩待验收。


## D068 持续供应契约
TDSupplierNetwork仍唯一供应权威。内部schema2读1（迁入空lines/line_serial，不复制旧货）；Profile仍9。lines有稳定supply-line:N、town_id/store_id/item_id、target_units(库存内部单位)、slots、enabled、managed；数组顺序为优先级。create/configure/remove/move为请求接口；line_rows/snapshot返回深拷贝，重复同源/同店/同原料拒绝DUPLICATE_LINE，非法容量/目标原子拒绝。手动改行收回托管所有权。
新批沿用orders及supplier-order:N，新增line_id；新job.seconds/elapsed为游戏秒，transit_minutes/transit_elapsed为游戏分钟；没有line_id的旧job仍是真实活动秒。钱先经Shop.branch_adjustment，真实源镇库存一次预留，完成经唯一receive_supply收货。连续单给主店显式continuous=true，旧调用保持边界限制。分店沿原receive_supply/成本/付款验证。
advance_active_time(real_seconds,game_minutes)统一长帧分段；Shell由真实clock差传游戏分钟。sleep在真实成功跨日后一次推进到08:00的余时，仅新产线推进，旧单无离线/睡眠加速。配置/存档校验区分版本、单位、目标引用、进度、幂等token，收款入库仍由Profile对中央账核验。
费用预算按store共享：所有持续行累计，同天关闭/开启不清零；分店还受budget_cents减今日采购限制。现货+在制+在途含旧工厂及已付世界货运，所有权不迁移。UI仅发意图。SupplierPanel为U正式入口；GameShell控制暂停，不能另启后台计时器。


## D069 材料、地区与调料盘接口
- `TDMaterialCatalog`：唯一新增材料注册表，`data/item/definition/recipes`返回深拷贝，`supplies(town,id)`读供应地区；`culture_tags`是来源文化，不用于供应判定。`culinary_materials.json` schema/revision1，未知版本/地区、重复节点、引用/包装/保质期非法会拒绝。旧运行ID不重解释。原250身份展示索引ingredient_index继续只读追溯，不作为运行供应表。
- `TDServiceCatalog.load_file`显式装配材料定义/费用，TDResearchRuntime增量安装既有3菜而不重复材料。原定义与新注册表职责见AI-079。四个库存大组保持与冰箱/工厂一致，细类在material.category。新的运行菜谱可带`cuisine_id:cn|eu|jp|sea|lat`及可选`seasoning_palette`；无字段旧菜按cn。
- `Shop.material_recipe_unlocks`是Research已解锁节点的只读投影，初次装配、研究changed和读档刷新；不是第二份存档。主料门槛沿用；调料不限研究进度。`stock_info`提供供应地区/标签/细类。报价与产线必须用Supplier catalogue规则，不直接读旧common_items/local_items作为权威。旧工厂兼容入口也按所在镇筛选，新正式入口仍为U五供应商。
- 付费旧单校验稳定材料ID、目标、付款凭证、量/成本/进度；不因新的产区规则拒收已付旧货。新起批必须重新通过报价，因此旧不合地区产线只能排空已付货。Shop仍唯一玩家钱物账，WorldEconomy只记录源市场库存/成本，不创建免费玩家材料。
- `TDCookingLane.recipe_spices/spice_choices`供实际绘制、命中矩形与控制器allowed_actions共用；谱面必需调料优先，随后菜系盘，模板只读、每锅独立。真实M6长按沿用session.pour_material→Shop消耗，不由UI改味觉/数量。归零灰显且不能点，取消不退已经加入的量。
- Shop/Economy可选`material_version=1`，省略表示旧材料范围；只允许新增ID的完整缺省迁移，不吞旧ID缺损。恢复时新品玩家库存0/空批次，源市场补默认新库存；当前版本漏项、部分字段缺损、未来版本均拒绝。Profile9/Supplier2/Research1不变，普通退出不保存，旧主动保存时点不变。


## D070 调料菜系采购权限
- MaterialCatalog.items[id].unlock_cuisines：调料必填、非空、去重的cn/eu/jp/sea/lat数组；只表达菜系使用，独立于supply_regions。注册表schema1/revision1增加必需内容校验，存档不持有这份模板。
- Shop.material_cuisine_unlocks是Profile从Research.snapshot().cuisines同步的只读用途投影（构造、changed、restore），不单独保存；独立旧测试入口默认cn。不能用它伪造研究或重复持久化。
- market_sells/buy与purchasable/purchase_ids使用统一condiment_unlocked判断；完整购物车先校验再扣款。Profile.buy/order_remote、Supplier.catalogue/quote/order/create_line/_start_batch及旧factory_products沿现有权威门槛。非调料原行为保持。
- consume_materials/receive_supply/已付供应货物交付不受新购门槛限制，旧调料批次/钱账不会删除或重扣。锁定旧产线显示“等待调料菜系开放”，已付批次继续。
- SupplierPanel只订阅当前槽Research.changed刷新货架，重配置与退出断开订阅。不修改研究；已打开面板可立即反映正式推荐事件。QTE继续按现有菜谱盘和真实库存呈现，不篡改已拥有调料的使用权。
