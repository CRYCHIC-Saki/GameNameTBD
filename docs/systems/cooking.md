# 完整做菜系统增量规格（Phase 1）

> 当前玩家流程以 DECISIONS D015、CONTRACTS 的 D015 小节为准：台面拿取/搬运、逐拍表自动完成M1–M7、双锅和简化HUD。本文旧自由工序、拖盘、返工、自建配方等公共方法保留兼容测试，不代表菜单仍可操作。当前生产权威时表为 `pc_operations.document_sheets`，模块权重为 `document_weights`；旧events时表仅用于历史回归。

## D014 操作与功能位契约（历史基线，玩家入口以D015为准）

- `pc_operations` 是 cooking_system.json 的操作配置扩展，`beat_sheets` 是同一权威中的可校验时间表。保留五类基础QTE，增加按拍命令/材料点击、方向切菜、引力控温配置；不是另一套菜品模型。当前生产UI使用PC配置，基础控制器兼容历史回归夹具。
- 厨房入口拥有共享节拍时钟、两个锅会话及一个砧板/手持备料会话；无Autoload。功能位只发稳定ID，厨房编排选择操作。手持状态只保存对象身份，不复制一份可变菜品。移动/暂停不重建会话。
- 食材跨会话转移通过模型方法预检两端状态、身份、份量、目标批次后一次提交；失败两端不变，重复转移拒绝。属性/切菜历史/品质随实例转移，模板不变；不触发第二次供料。
- 同菜允许 `heat/boil` 与一个 `stir/season/starch` 工序并行。各操作有独立operation_id与完成去重，效果只在各自完成时应用。取消清理两轨；炖煮离开后继续，暂停冻结。时间表从共同下一强拍对齐，以秒推进并切分事件边界，不累计帧数判定。
- QTE结果新增成功落刀方向数组、实际调料点击序列、点火游标位置和连续控温剂量；界面不能直接写属性/评分。切型由模型根据落刀事实推导；调错材料按实际材料和次序影响味型。未操作不伪造成功。
- 世界主流程：料箱E拿取→砧板E放下/打开→备好后取走→灶台E投料/打开→出锅→E取盘→出餐台E试吃。空手可再次打开灶台。自由漏项仍可交付并解释；每次交付仅一个成品事件。

### 当前PC规则与版本

`TDCookingSession(...,options={pc_controls:true})` 启用本配置，v3请求与独立评分不变。`transfer_to(destination,instance_id,transfer_id)` 保留源instance_id与处理事实，目标重新分配方案local_id；两端忙碌、缺目标、超量、重复转移不变更任何状态。`pending_operations` 按operation_id暴露独立任务；`cancel_operation(id="")`可取消指定轨或全部轨。

| 模块 | 实际输入/结果 | 当前建议值与映射 |
|---|---|---|
| M1 方向切菜 | 空格按拍、A/D循环横/竖/斜；仅成功落刀增加fine，品质独立 | 计划1–12刀；1刀片、2同向条/转向块、3+丁；fine最多8刀归一，斜刀释放加成.1 |
| M2 点火 | 扫动游标到中央按空格；cursor产生实际初始锅温 | 对齐下一强拍，±50/100ms；不再使用旧蓄力点火 |
| M3 连续指令 | 每拍方向键、末拍空格；下油/翻炒/勾芡/发酵共用，蒸制复用按住时长 | 左WASD、右方向键；错一步Good、多错Miss；蒸制约4秒 |
| M4 炒制控温 | 鼠标归一位置施加引力；靠近弱、按住强、离开清除；与手部轨并行 | 16秒，1秒扰动周期；稳定占比>80% Perfect、≥50% Good |
| M5 炖煮 | 同一连续接口，更宽目标/更慢扰动；返回世界仍运行 | 16秒，2秒扰动周期；世界HUD显示剩余时间 |
| M6 精确调味 | 逐拍实际点击盐/糖/油/淀粉；结果记录材料与beat_index | 默认目标盐→糖→油；单次份量.1可调.01–1；错料实际改变味型，无点击不加料 |
| M7 出锅 | 按住空格并在绿区松开；完成成盘，随后实际搬运交付 | 中心1秒、超时4秒；提前/过晚对应既有欠火/额外受热规则 |

以上参数PROPOSED。Perfect/Good窗口、权重、漂移、释放与手法效果都在pc_operations；未篡改源资料。M4表述冲突、两刀形态与双菜空格裁决详见D014。精确调味先校验整组事件，再提交材料；读取/评分不触发二次效果。普通下油使用方向QTE，实际失败品质仍进入菜品，不返回固定高分。

TDBeatSheet校验BPM、有限拍号、操作引用、同拍同轨冲突；当前炒菜/蒸菜两表仅调度真实操作，留白和热/手两轨可并行，BUSY明确终止该表。脚本配置按共同下一强拍启动；辅助窗口×1.5，练习控温明确标记。音轨为循环16拍自制PCM，四拍强弱、共享可视拍钟与±250ms输入补偿；物理耳机/显示器/键盘同步NOT_RUN。

PC自建方案schema2，文件容器仍schema1并可读取旧方案1；新增刀数及真实调味次序/local_ids，不存操作成绩。重做时add/cut提示去功能位备料，后续步骤沿用真实QTE。模型支持仍保持旧分批/保温/SAN接口，但当前PC界面没有全部旧开发控件；本轮着重功能位和操作，不能把隐藏旧控件写成可点击功能。

## D013完整机制规格与历史操作说明

以下为前一检查点的规则/接口记录。六属性、反应与评分继续有效；旧预选切型、滑条控火、点火/出锅输入及165项证据不能覆盖上面的D014操作与最新阶段报告。

状态ENGINEERING_READY / PLAYTEST=PENDING，完整165项证据见PROJECT_STATE；旧原型76项证据保留历史。用户D013确认doc/agent_prompts/Phase_1.md A–J机制及可走动2D像素厨房、灶台E交互、每种QTE对应烹饪动作。仍不做经营/世界。

## 已确认增量

GRILL_RESULT=RESOLVED，实际使用grilling文件无版本字段。2026-10-09三题用户全部采用推荐：SAN≥60倍率1，0–60倍率.6+.4*SAN/60；仅交付时低SAN<30且整盘QTE达到Perfect档和存在候选才一次抽变体；返工/重看不重抽，消耗按配方明示事件记录一次，两套历史Tier不强行统一；盘内自由摆放不改分，拖动越界不判，盘外松手该份报废。既有D006/7/8自由工序、切型/品质分离与评分仍有效。正式番茄炒蛋不伪造官方阴暗版，变体验证只TEST_ONLY。

## 并行归属与接口

主集成：src/app、src/kitchen的完整面板/协调器、src/platform配方库、tools、project.godot、导出、文档、共享集成测试。规则线：src/content/cooking_catalog.gd、content/cooking_system.json、src/cooking/cooking_session.gd及内部完整规则对象、规则/内容/SAN单元测试。QTE线：src/qte/cooking_qte.gd与其新增单元测试，旧两类探针不改。像素厨房线：src/world、assets/kitchen、test_kitchen_world.gd。共享文件由主集成合入，不并行import。

### v3入口与规则接口

复用TDCookingSession公开入口，v1探针/v2原型仅作为历史回归。schema_version=3数据由TDCookingCatalog.load_file/load_data校验，data()->深复制，recipe_ids(include_test:bool=false)->Array，for_recipe(id)->Dictionary（完整运行定义+selected_recipe_id）。唯一当前系统权威为content/cooking_system.json，旧JSON保留明确旧版本入口；原towns只读。

会话构造TDCookingSession.new(sid,gen,config,options={san:100,random_source:TDBusinessRandom})。新版本begin仍用TDRequest，schema_version=3。即时操作 add{ingredient_id,amount:1,batch_id?}、merge{source_batch,target_batch}、container{kind:"normal"|"insulated"}、rework{}、deliver{}、discard{}。QTE操作由配置定义：cut{instance_id,shape}、preheat{}、stir{}、heat{}、boil{}、season{ingredient_id,amount}、starch{}、ferment{}、plate{}；批次可用batch_id，默认main。begin返回STARTED.data.qte_config，完整有效SAN缩放参数已在其中，QTE独立接收。即时返回APPLIED/DELIVERED。

complete_operation(TDOutcome)只验证正确身份/类型/有限值/完成状态并提交一次；cancel_operation清未提交操作；advance_time(delta)显式推进冷却/暴露；snapshot().to_dict()纯读取。额外提供move_plating(piece_id:String,position:Vector2,drop:bool)->TDOutcome，坐标归一化[-1,1]圆盘，drop且长度>1报废，位置不改属性。阶段状态preparing/operating/plated/delivered/discarded/cancelled；plate只成盘不交付，rework保留全部历史回锅，deliver只一次。支持分批处理合并，输入稳定instance_id；实例id由session自动分配，snapshot.ingredients字典按instance_id索引，含ingredient_id/name/amount/batch_id/shape/fine/temperature_c/texture/flavor/aroma/history，不能加料回填旧处理。

快照兼容评分字段dish_attributes:{flavor:7×4,temperature_c,aroma,texture,completion,harmony,dominant,compound},scoring_rules、base_reasons、missing_required；另recipe_id,recipe_version,is_custom,steps,history（before/after）,batches,plating:Array[{id,position:[x,y]}],events:Array、san_context、san_spent、variant_id、custom_plan。custom_plan只含版本、recipe_id、ingredients与有序operation/parameters，不含成绩/随机结果；前端配方库负责命名和版本持久化。

配置包含 ingredients/recipes/operations/qtes/reactions/rules/scoring_rules/customers/variants 和 active清单。食材字段覆盖category/subcategory/quality/base_flavor或base_tastes+slot_profile/texture/aroma/region/special。食谱至少两种明显不同结构TEST_ONLY内容，公开食谱不混入test标记。所有新增数值PROPOSED，大小与份量单位在配置注明。操作/反应不是菜名特判。配方需求单独定义，顾客需求沿用v2加可选ingredient/step声明。星级阈值为配置建议，不来自88分案例。

### 五QTE接口

TDCookingQTE.new(request:TDRequest,config:Dictionary,clock:TDClock,random_source:RefCounted)。start、input(sequence:int,timestamp_sec:float,action:String,pressed:bool,value:float=1)、update、finish、cancel、reset(request,config,clock,random_source)，release_input。TDOutcome data必须含schema_version3/session_id/generation/operation_id/kind=request.operation/qte_kind/status/quality/grade/elapsed_sec/reason。过程data含progress/ready_to_finish及对应实际指标。finish只一次。config.kind为charge/rhythm/window/maintain/sequence。

共用时间基准：绝对clock.qte_sec，参数秒，input_offset_sec正值表示扣除输入延迟。根面板采用固定结束边界切分推进；QTE update提供remaining_sec，右端有效窗口不提前finish。输入action primary用于蓄力/节奏/窗口，up/left/down/right用于顺序，adjust+value[0,1]用于维持；按键回显与重复sequence拒绝，按住产生上升/下降沿。维持需要配置扰动且按时间积分，不能初始静止即自动满分；保留旧原型heat行为供回归。

配置建议：charge timeout4、目标持有1.2–1.6秒；rhythm8拍/.5间隔/1秒预告/Perfect.06 Good.14；window目标1.8秒、Perfect.06 Good.14、timeout2.5；maintain6秒、目标.4–.7、可注入随机相位的可见扰动；sequence四方向明确预告顺序、时间上限5秒、正确率分档。非时间型单独定义档位。音游参考只学习拍点预告/命中线/按住松开/方向提示，不复制曲目或美术。

### UI及存储

TDKitchenWorld发cooking_requested(station_id)，root打开同一套完整厨房UI。关闭UI返回场景不销毁未交付两会话；主动暂停或失焦冻结全部。WASD/方向在行走态移动；UI单菜Space主操作，双菜左W/右Up主操作，左WASD/右方向顺序；键盘事件每次仅分配一个槽位。维持鼠标滑条或左右键调节，显示实际控制量和目标带。

界面可选择普通/TEST_ONLY配方、食材、处理目标与批次、所有工序；有两个真实同时推进的QTE面板、只读属性/原因、可拖摆盘、返工/交付、SAN测试、自建配方命名/保存/加载/另存版本。存储只保存方案，不自动重播QTE，不覆盖未知/坏文件；测试路径隔离。

## 验证边界

完整规格18项AC加世界/动作两项详见阶段报告，自动/工程通过；像素场景、动作、供料和唯一成品均已真实场景验证。人工音画/设备同步与玩法体验独立PENDING。

## 最终接口细化与建议参数

- 本文的v3是数据版本；配方库/方案schema_version=1，不是旧v1探针。方案原料带local_id，add/season参数带local_id，cut带target_local_id；运行请求前由Lane转成此次instance_id，不能用模板ID猜同批次目标。方案只存原料/份量/批次及有序操作参数，没有成绩、输入录像或成品。保存检查本地ID唯一、引用先后与用量一致。新版本追加记录，不覆盖旧版本；坏文件/未知版本不自动覆盖。
- snapshot新增pending_operation、recovery_sec、plating_dragging、fermentations。add和season完成返回instance_id/local_id。摆盘position为已提交圆内位置，preview_position是拖动中位置；未松手时禁止交付，暂停取消拖动回合法位置。初始所有份数在盘内。
- sequence完成只是发酵操作完成；真实发酵暴露继续由advance_time推进，fermentations给出剩余秒数，达到温度/时间条件才改变属性。切后氧化也是显式游戏时间；四热反应在完成时检查温度并累计符合条件操作时间，每食材每反应一次。这些是游戏规则，非物理仿真。
- 过早出锅减少香气；过晚增加加工剂量；超时兼有两种后果。具体系数在rules.plate_*。不直接改满意度，缺香仍按D008分层。
- 多实例细碎/口感要求采用偏差最大的匹配实例，避免一份未处理原料被均值藏住；ASSUMPTION，可调策略。ingredient需求比较总标准份，step需求比较次数；正权重归一，未声明无罚。星级阈值0/40/55/70/85为PROPOSED，不使用案例88反推。
- 维持控制每个绝对1/240秒格计算扰动并对区间积分，渲染分片不改变同输入时间线的结果。UI滑条0–100%持续输入；左右键每按调整5%，自动重复不算新输入。双菜主动作左W/右↑，顺序左WASD/右方向；单菜主动作空格。Esc和失焦冻结，关闭界面返回走动时工序及冷却继续。
- 节奏错拍/顺序错误惩罚权重error_weight=1为建议；余量>=0、全部Miss可提交真实失误但不会伪造成功。切伤概率/延迟/SAN代价外置，只在低品质切菜事件抽业务随机一次。
- 整盘Perfect的首版资格算法为所有已完成工序quality≥0.95且食谱必需项满足（PROPOSED保守初值），返工不能洗掉此前失误；阈值外置。该实现细节不冒充用户已给出的数值表。
- 音轨是自制占位PCM节拍，使用AudioServer的启动延迟估计修正QTE/视觉起点，输入偏移±250ms，正值抵消较晚按下。真实设备校准仍未验收。参考[Rhythm Doctor官方](https://rhythmdr.com/)的节拍预告与[SEGA官方操作说明](https://miku.sega.jp/arcade/en/play.html)的按键/保持提示，只借鉴交互，不复制音乐美术。

## 扩展与外部接入

新增食材：在ingredients填完整模板及唯一ID，加入active.ingredients。新增已支持机制的食谱：定义required_ingredients/steps、建议流程、香气与理想区间，加入recipes和active.recipes；先标TEST_ONLY并跑content/cooking套件。新增工序语义需代码与测试，不能仅添加未知字符串。当前两个测试配方为冷拌黄瓜、反应试锅；正常菜单隐藏测试食谱/食材/自建测试方案。

供料调用begin(add/season)，由模型校验单食材总量上限，快照consumed_ingredients给实际身份/份量/批次；未来库存适配器据一次性操作ID消费，UI不再扣库存。成品以dish_id/session_id/generation追踪，Lane转发唯一dish_delivered；经营只接此事件，评分不发奖励。events包含反应/切伤/消耗/变体/识别等事实，当前无全局事件总线或成就服务。

全部新增系数PROPOSED。原始“五维/六项”、Tier差异与可选支线/主线冲突来源保留于DECISIONS；氧化的“涩”未映射成第八味，也未擅自等同苦味。原文支持的苦增/鲜减/甜减按独立已配置效果实现。
