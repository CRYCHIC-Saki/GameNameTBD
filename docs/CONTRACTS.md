# 公共契约：v3完整烹饪，兼容v1/v2历史入口

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

## D023 餐厅面积、雇员与分店

- 面积 id 是 small、medium、large、huge，占地 3×4、4×6、6×9、12×18。店内列数和行数是占地乘 2，并且都不小于 8。主店默认 small，生成在中心路口旁边、不压路的空地。`TDTownMap.build` 的中心格仍是路。
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
