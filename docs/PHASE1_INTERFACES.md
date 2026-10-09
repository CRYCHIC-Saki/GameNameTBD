# Phase 1 近期接口（实施契约）

共享文件与集成负责人：主 Agent。规则/内容、QTE、评分工作线各拥有其目录和新增单元测试；不互改文件、不改 project.godot。保留 Phase 0 probe 接口用于回归，主入口增加正式原型厨房；不复制应用、时钟、结果或存储框架。

## 配置与会话

TDRecipeCatalog：load_file(path)/load_data(Dictionary) -> TDOutcome；data() -> 深复制 Dictionary。唯一运行源 content/cooking_prototype.json，schema_version=2，scope=COOKING_PROTOTYPE，所有数值 PROPOSED。

TDCookingSession 原类扩展：构造第三参接受既有 TDTemplate 或校验后配置 Dictionary。v1 保留。v2 begin(TDRequest) 读取 request.parameters（新增可选 Dictionary），schema_version=2。参数：add {ingredient_id}，cut {ingredient_id:"tomato",shape:"chunk"或"dice"}，season {ingredient_id:"sugar"或"salt",amount:1}，heat {}，plate {}。add/season/plate 是即时操作；cut/heat 返回 STARTED 并占用当前操作。initial 材料为空，UI提供番茄/鸡蛋添加按钮。

complete_operation(TDOutcome)：data必须有 schema_version=2/session_id/generation/operation_id/kind/status=completed/quality[0,1]/elapsed_sec，cut额外 hits/perfect/good/miss，heat额外 heat_dose（火力×秒）、end_power。只应用一次；cancel_operation()结束当前工序不应用未完成效果；cancel()关闭会话。snapshot().to_dict() 返回下述值。plate结束加工，交付由UI调用独立评分（可多次只读计算），不重应用效果。

v2快照：schema_version=2,scope,session_id,generation,revision,state=preparing/operating/plated/cancelled,operation_id,ingredients（id→{shape,fine,texture:{A,B,C},...}）,steps,history（每项 operation/before/after）,dish_attributes:{flavor:7行×4列，temperature_c:float,aroma:Dictionary[String,float],texture:{A,B,C},completion:float,harmony:float},missing_required:Array[String],base_reasons:Array[Dictionary],scoring_rules（来源配置深复制）。snapshot是纯读取，温度通过 session.advance_time(delta_sec)推进冷却，工序效果在完成时提交。

配置包括 customers:Array，每项{id,name,description,requirements:Array[Dictionary]}。需求项{id,label,kind,min?,max?,weight,scale?}；kind=flavor(temp通过temperature)、texture、fine、aroma；flavor用taste:int/slot:int，texture用axis可选ingredient_id，fine必需ingredient_id，aroma用tag/min。temperature kind 为 temperature。score偏差=超出区间距离/scale×100，clamp0–100；aroma缺标签100。positive weights归一化；零权重不扣。scoring_rules={quality_weight:0.35,harmony_weight:0.25,requirements_weight:0.4}。

## QTE

TDRhythmQTE、TDHeatQTE 为 RefCounted，constructor(request:TDRequest, config:Dictionary, clock:TDClock)。start() -> TDOutcome、input(sequence:int,timestamp_sec:float,value:float)->TDOutcome、update()->TDOutcome、finish()->TDOutcome、cancel()->TDOutcome、reset(request,config,clock)->TDOutcome、release_input()->void。timestamp为TDClock.qte_sec同域绝对秒，窗口相对start记录。update返回状态，完成后 finish只返回一次 completed 结果；重复返回ALREADY_FINISHED。pause由clock.paused读取，input拒绝，恢复需release后的新输入。config都从运行JSON外置。

Rhythm config: beats=8, interval_sec=.5, lead_in_sec=1, perfect_sec=.06, good_sec=.14,input_offset_sec=0。绝对输入时间减offset后匹配拍点；一次上升沿只消费一个拍点，连发或同sequence拒绝，不重复判定；释放value0不落刀。update过窗记miss，全部窗口结束可finish。正offset用于补偿按下较听到的拍点晚的设备延迟。

Heat config: duration_sec=6,target_power_min=.4,target_power_max=.7。value[0,1]火力，按时间段积分heat_dose，quality为目标区间有效秒/总时长。UI空格按住升火（value1）、松开0.5，可用滑条精调；初始0.5。输入前积分旧火力至timestamp；长帧截终点。update进度，finish在6秒终点返回heat_dose/end_power。没有视觉随机消费业务随机。

## 评分

TDCustomerScorer.evaluate(snapshot, customer) -> TDOutcome data {satisfaction,deviation,quality,harmony,reasons:Array[{id,label,penalty,message}],requirements:Array}。对无v2菜品保持NOT_IMPLEMENTED给历史probe；对v2坏输入返回INVALID_DISH/INVALID_REQUIREMENTS等。基础Q/H由会话一次性派生，评分不改它们。需求未声明不推断。原因中分别列出 base_reasons（基础层）与 requirements（需求层）。

## 已落实边界与实际字段

- recipe.required_steps固定校验为[cut,heat]，本轮不宣称通用任意配方转换器。config存纯值、模板副本、会话独立复制，任何快照均深复制。
- request.parameters默认{}；旧v1构造兼容。add/season即时APPLIED，plate即时PLATED且result_ready只发一次；cut/heat STARTED→complete_operation APPLIED。重复完成ALREADY_FINISHED、旧身份STALE_OPERATION、取消CANCELLED、更粗切型COARSER_CUT、忙碌BUSY、调料超量AMOUNT_LIMIT、坏结果INVALID_RESULT，拒绝不应用效果。
- history每项operation/operation_id/parameters/before/after/result；before/after为六属性对象，切型细碎度另存ingredients和parameters，不构造全菜唯一fine。steps保存真实工序事实，base_reasons从这些事实派生，不在快照读取或评分时再次扣分。
- good_quality=.6、initial_power=.5已外置。完成结果cut命中计数/quality必须一致且不能过早；heat剂量与品质必须物理上可共存。不是从UI传入固定满分。
- 厨房长帧在QTE结束点切分；节奏最终Good右端仍接受输入，越过端点后才自动提交。加热结束余量正常冷却。plate冻结这次交付快照；不会重复计温度/惩罚。
- 本轮输入偏移UI±250ms，正值从输入时刻扣除；音轨开始延迟加到拍点。开始、输入、过程更新、完成、取消、reset均有独立测试。取消/重开销毁控制器和局部音轨，不复用旧操作身份。
