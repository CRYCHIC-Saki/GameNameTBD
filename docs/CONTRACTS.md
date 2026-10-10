# 公共契约：v3完整烹饪，兼容v1/v2历史入口

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
