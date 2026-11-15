# D059 餐厅体验反馈

## D071 屏幕方向与出餐交接（2026-11-11，工程交付／人工待试玩）
使用 grilling：C:/Users/Administrator/.codex/skills/grilling/SKILL.md，及 godot-gdscript-patterns 同根 SKILL.md，均无声明版本。只读审查确认旧正式厨房提前结算；用户明确真正送桌才停耐心。GRILL_RESULT=ANSWERED，无其他阻塞；不实施此前供应商合同提案。
- AC-D071-001：主店/分店餐厅 WASD 沿屏幕四向，斜走速度归一；疾跑、墙碰撞及慢前后步频保持。真实输入/独立绘制投影验证。
- AC-D071-002：真实厨房/厨师做完只入出餐口，钱款、评分奖励和用餐在真实送桌才发生；玩家与服务员共用唯一盘状态。真实场景集成。
- AC-D071-003：取盘认领互斥、送错客/远程送盘/重复送盘拒绝；玩家可在出餐口退盘或丢弃。规则与场景测试。
- AC-D071-004：出餐/持盘耐心继续；超时原盘保留并可匹配后续同菜订单，无二次耗料；暂停冻结，隐藏餐厅员工继续；收夜明确清理。
- AC-D071-005：未清理盘阻止边界保存/跨日，原存档格式兼容；原资料不变，真实日志和人工待试玩分开记录。

实现：主店和分店巡视餐厅只复原 input_transform 为单位变换，保留原投影逆矩阵、速度预算、碰撞、Shift1.6、140/224步态距离。正式 Shell 启用 TableService；实际厨房/真实厨师的 delivered 快照只排盘，Shop仍唯一负责送桌评价/钱账/家庭付款。runtime队列采用dish_id和独占carrier；复制查询，拒绝重复入盘/送出/报废重放，超时保留并重新匹配，员工撤任/失去目标安全退盘。出餐口E取放，桌边E送，出餐口Q报废。手持餐盘及待取/端送文本真实接入；教程也需把试做送到阿铃桌边，离开厨房收起厨房动作立绘。详细接口见CONTRACTS D071，参数/技术默认见AI-081。

已执行证据（各命令均包含导入→149项资源加载→GUT计数门槛）：
- `table-service-03`：3文件16/16，包括真实厨师→出餐口→玩家/服务员送桌、超时转单、重复/错桌/距离/暂停/报废/夜末/保存、真实键盘鼠标教程试做，以及分店室内四向移动。
- `pre-export-20261111-205927` movement：4文件34/34，墙体滑动不超过180px/s、Shift288px/s、场景往返及布局。
- `table-service-rules-stride`：`table-service-regression -ShardCount 5 -ShardIndex 3`，2文件27/27，577断言，独立经营规则与主角原步频。
- `table-service-checkpoint-axes`：同套 `-ShardCount 5 -ShardIndex 0`，2文件11/11，846断言，原整槽回退/主动保存/02:00边界及八方向移动。
- `table-service-game-final`：同套 `-ShardCount 10 -ShardIndex 1 -TimeoutSeconds 1200`，正式入口7/7、185断言、317.159秒。真实集市采购、菜单、手动QTE、出餐口取盘、送桌、家庭扣款/小费退款守恒、税费与等级日结、保存重启连续3日通过。保留3条既有Float/Int比较警告，非失败/跳过。
合计95个独立用例、3048断言，exit0、无零测试/失败/跳过。AC-D071-001至005工程PASS；真实人工手感与服务压力仍PENDING。

Compatibility 实机：`tools/table_service_probe.gd` 真实main.tscn、隔离新档、实际输入，39项/6图、exit0、无运行错误。核对了取盘前/后、手持餐盘、阿铃可达座位和收菜后真实83.8分（不是硬编码成绩）。最终证据 `artifacts/table-service-20261111/gpu/final.*`，音频Dummy，不能当人工设备试听或玩法平衡验收。
本地导出：`pwsh -NoProfile -File tools/export.ps1 -CheckSuite movement -CheckTimeoutSeconds 300` exit0；614运行资源，包含新table_service，启动/退出3×4项与真实EXE headless94项通过。build/TownDiner.exe/.pck 于2026-11-11 21:00更新。原始资料/罗厄保护范围43文件哈希一致，真实玩家档未读写。

保留的失败/未完成记录：`table-service-01`因测试局部变量缺静态类型导致零用例，被检查链以exit1正确拦截；修复后02/03通过。扩大回归 `table-service-regression-0` 600秒超时，不能记整组通过。`regression-1`旧三日测试还期望厨房SERVED，保留失败日志并主动终止(exit-1)，已改成真实取盘送桌；r2运行遭环境重载中断，无完整报告，不计通过。首次导出检查也在环境重载中断，最终导出已完整复验。

人工试玩PENDING；全仓/远程CI未运行。本轮仅送餐规则和移动，不改变供应商合同、正式分店手工接管或新美术。试玩：1.运行本地EXE；2.餐厅WASD/斜走/Shift检查方向；3.厨房做好菜并放到出餐口；4.回餐厅E取盘，桌边E送；5.检查待送耐心/超时保留，或雇服务员观察实际取送。交付后停在本轮反馈点。


## D059-R4 坐姿与凳面投影（2026-11-06，工程完成／用户视觉确认待定）
用户明确R3腿与凳子透视仍错误。实际使用已读grilling、godot-gdscript-patterns、imagegen；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS，属于明确视觉缺陷。R3的工程PASS未获用户视觉认可。本轮把入座姿势和红垫木凳作为同一投影下的组合绘制，空座继续独立显示；不重复叠空凳，不拉长腿。
- AC-D059-R4-001：四身份两朝向保持短腿比例，臀部压在坐垫上，近腿越过相应凳面边缘、远腿在后；空凳与有人坐的姿态只绘制一次，场景截图/入座过渡核验。
- AC-D059-R4-002：R3桌凳间距/同一座位ID/落座点单时机不变，组合等比缩放、同步镜像、清理及重开无残留；专项与实际导出检查。
- AC-D059-R4-003：保留旧图及失败/未认可记录，真实数量与人工PENDING分开，不提交推送。

实现：v4入座组合包含同一投影下的人物与凳子，近腿越过对应边缘、远腿后置；正式桌类进入坐下后半段/已坐状态只绘制组合，原侧空凳跳过，离座/清理恢复。图集1261×1247明确按列630/行界600取图，避免帽子串格；整体等比108px、凳脚底部锚点与R3位置一致。空凳显示尺寸调至约53.57×44.48px以衔接；非桌类仍走旧独立坐姿。原图、物理移动/Shop唯一订单/存档均不改。源说明OCCUPIED-V4-SOURCE.md；首稿凳子过小未采用，辅助读图取半高越界已修正，不当作引擎验收结果。

最终检查：`pwsh -NoProfile -File tools/check.ps1 -Suite seated-art`，3文件、20/20、1089断言、13.834秒，无失败/跳过，导入/加载/测试exit0。最终报告artifacts/check/pre-export-20261106-165251。Compatibility场景74项/22图，exit0、stderr空；真实入座/同ID点单、四身份两侧、空凳抑制/画面区域可见通过，开发查看了近景，但透视观感仍未获用户确认。证据artifacts/d059-r4/gpu/。

`pwsh -NoProfile -File tools/export.ps1 -CheckSuite seated-art`通过：569资源（含v4）、启动3×4、实际EXE headless94项、exit0，build/TownDiner.exe/.pck于16:53:25更新。AC-002/003工程PASS；AC-001的显示接线PASS、视觉接受PENDING。未跑全量/本轮EXE GPU/远程CI。协作98路径及git diff --check通过，写入锁释放，未提交推送；原资料/真实档未操作。

试玩：启动本地游戏 → 开店观察入座 → 查看近腿越过凳边、远腿遮挡以及空座恢复。下一步只处理本轮视觉反馈，不宣布此前多次视觉问题均已由机器测试证明解决。

## D059-R3 桌凳间距（2026-11-06，工程完成／人工待试玩）
用户要求把凳子远离餐桌试效果。实际使用已有grilling、godot-gdscript-patterns和imagegen技能；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS，属于明确视觉调整。原素材只读，新桌凳单独绘制，人物沿原比例随坐点移动。
- AC-D059-R3-001：凳子与餐桌有可见间距，人物臀部仍对齐新坐点；两侧/镜像同步，不改身体比例。真实四身份/两侧截图核验。
- AC-D059-R3-002：实物、装修预览共用模型，旋转中心/家具格占地/ID不改；真实入座与后厨同ID订单通过，不改保存规则。专项测试与导出验证。
- AC-D059-R3-003：保留旧图、真实日志与未提交成果，工程检查与人工观感分开；本轮不提交推送。

实现：新增独立桌/凳图集，原桌凳合图和人物素材只读。两侧凳心各向外12.96px、向前8px，人物臀部与Guest接近位置跟随同一模型锚点；83.52px原比例不改。桌面保持居中，凳子仍在原显示边界内；目录/实物/预览共用分件绘制，原Layout占格/容量/ID不变。源图说明assets/town/dining-table-stool-separated-v1.source.md。

验证：`pwsh -NoProfile -File tools/check.ps1 -Suite seated-art`，最终artifacts/check/pre-export-20261106-163046：3文件、18/18、724断言、13.833秒，无失败/跳过，导入/加载/测试exit0。Compatibility真实餐厅66项/22图、exit0、stderr空；实际四身份/两侧截图已目检，腿部可见2800–3038个像素，新间距下不强制维持旧R2遮腿数量。真实进店/坐下/同ID后厨订单仍通过。证据artifacts/d059-r3/gpu/及gpu.log。

`pwsh -NoProfile -File tools/export.ps1 -CheckSuite seated-art`通过，567运行资源包含新图，3次启动各4项及实际EXE headless94项PASS、exit0。build/TownDiner.exe/.pck于16:31:19–20更新。AC-001/002/003工程PASS，人工观感PENDING，未重跑全量、实际EXE GPU或远程CI；原资料和真实档未操作，不提交推送。95路径协作检查与git diff --check通过，锁释放。

试玩：启动本地build/TownDiner.exe → 开店等客人坐下 → 对照桌凳空隙及身体位置；当前间距为试验初值，下一步只处理本轮观感反馈。

## D059-R2 层次遮挡修订（2026-11-06，工程完成／人工待试玩）
用户明确：R1腿部比例错误，阿玲/老陈腿朝向错误，原投诉主要是贴图遮挡。R1视觉验收未获用户认可，撤销强制鞋底接地及由臀脚距缩放的假设；不重画动作，恢复v2坐姿与原等比尺寸。实际读取grilling与godot-gdscript-patterns；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS，修复范围明确，无需新增产品决定。
- AC-D059-R2-001：恢复原可爱短腿比例，具名角色使用同一整幅坐姿的躯干/腿，随座位一起镜像；不能单独旋转或拉长下肢。尺寸/镜像检查和四身份两朝向真实GPU截图。
- AC-D059-R2-002：原图只读；家具后层→人物→桌面/桌沿/桌腿前层按空间遮挡人物下身，躯干/头手不被重画家具误盖。非相交处不出现桌面片块或重复家具，家具旋转共用同一变换。用真实渲染像素对照（有/无人物）证明遮挡，不只断言锚点。
- AC-D059-R2-003：真实落座/同ID订单、原移动/保存继续可用，必要回归与本地导出通过；人工观感PENDING，不把测试通过等同最终画面认可。

实际实现：切回v2，83.52px等比显示；全身一起随座位镜像，不单独旋转腿。坐点取坐垫内侧，腿进入桌下；FurnitureModel定义桌面/围沿/近桌腿前层与人物下部朝桌侧的交集，Restaurant在人物之后重绘对应原纹理。保留外侧衣摆、头手，修正旧draw_polygon对AtlasTexture整图UV误用。原v1/v2/v3资源均未改，v3不再进入运行包；物理点/座位ID/真实落座时机与钱物保存不改。

API参考Godot官方[Geometry2D交集](https://docs.godotengine.org/en/stable/classes/class_geometry2d.html#class-geometry2d-method-intersect-polygons)与[CanvasItem绘制](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-method-draw-polygon)，以锁定4.7.2实际Compatibility执行为准。第一轮17/17通过，但目检发现桌边穿过外侧衣摆，随后将遮挡收窄到朝桌一侧并内移坐点；首轮报告d059-r2-first保留，不当作最终图形结论。

最终GPU：66项/22图、exit0、stderr空；四身份×两朝向，独立比较“同场景空桌”和“真实坐姿”截图，原素材不透明下身中有1607–1834个屏幕像素被真实桌层遮住，头部6746–9418像素仍可见。该对照不调用生产遮挡多边形生成测试预期，证据artifacts/d059-r2/gpu.log及gpu/；场景仍真实从来访/落座到同ID厨房订单。截图开发目检通过不等于用户已认可观感。

最终检查：`pwsh -NoProfile -File tools/check.ps1 -Suite seated-art`，3文件、17/17用例、712断言、10.052秒，导入/加载/测试exit0，无失败/跳过/解析错误。最终报告artifacts/check/pre-export-20261106-135348。`pwsh -NoProfile -File tools/export.ps1 -CheckSuite seated-art`通过，565资源，启动3×4及实际EXE headless94项PASS、exit0；build/TownDiner.exe与.pck于13:54:19更新。本轮未重跑实际EXE GPU和全量旧用例，不沿用R1的GPU94项作为本轮结果。协作92路径PASS，git diff --check exit0，锁释放，未提交推送。

AC-001/002/003工程PASS，用户观感PENDING、远程CI NOT_RUN。试玩不超过三步：启动build/TownDiner.exe → 开门等食客落座 → 检查桌沿挡住桌下腿部、衣摆/头手保留以及具名角色朝向。下一步仅本轮反馈，不继续新阶段。原R1长腿方案明确被用户否定，不把历史PASS视为当前视觉验收。

## D059-R1 下肢与坐垫（2026-11-06，工程完成，人工待试玩）
用户反馈腿仍全部在凳子上；撤回D059-001仅锚点通过即可证明坐姿正确的判断。实际读取grilling、godot-gdscript-patterns、imagegen技能；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS，本轮为已明确视觉缺陷修复，无新增玩法决策。
- AC-D059-R1-001：新增只读坐姿图集必须有弯曲的大腿、垂直小腿及鞋底；男女三衣色及阿铃/老陈、四旋转的臀部接坐垫，鞋底接地面（桌椅实测差36.08736px），不能通过拉伸整张图改变长宽比。坐标回归与真实GPU近景联合核验。
- AC-D059-R1-002：真实入座/后厨同ID订单继续成立，已修正输入/保存不变；通过必要场景测试及真实EXE验证，新图进入发布包，旧图保持只读。
- AC-D059-R1-003：记录真实检查数量、退出码、截图与人工PENDING；保留旧失败证据，不把机器通过当作用户观感确认。

实现：新v3图集有实际下垂的小腿，原图不改。FurnitureModel同时对齐臀部和鞋底，按两接触点等比缩放；取消固定83.52px高度。男女三衣色及具名人物复用，落座过渡、旋转、Shop订单时点不改。选用图的透明alpha已读取核对，运行时无工具预览背景。

专项`pwsh -NoProfile -File tools/check.ps1 -Suite seated-art`：3文件、16/16用例、836断言、9.525秒、无失败/跳过，导入/加载/测试exit0；最终证据artifacts/check/pre-export-20261106-132512，早一轮d059-r1-art也通过。覆盖双接触点、等比/旋转、真实入座订单及原装修交互；未重复全量或整份D059存档套件。

Compatibility真实场景：tools/restaurant_feedback_probe.gd，50项/22图，exit0、stderr空；人工查看了男女/阿铃/老陈左右姿态，膝盖弯曲、小腿在坐垫下方、鞋底靠地，普通进店到后厨同ID流程通过。证据artifacts/d059-r1/gpu。这里的截图目检是开发检查，用户实际游玩观感仍PENDING。

`pwsh -NoProfile -File tools/export.ps1 -CheckSuite seated-art`通过；新图显式进入565资源白名单，3次启动各4项及实际EXE headless94项通过、exit0。build/TownDiner.exe与TownDiner.pck于13:25:41–42更新，需同目录。AC-001/002/003工程PASS；人工PENDING、远程CI NOT_RUN。旧D059的单臀部检查不能替代本轮下肢验收。

试玩：启动本地build/TownDiner.exe → 开门等食客坐下 → 查看双腿是否自然垂在凳子前、鞋底是否落地。下一步仅本轮视觉反馈，不推进新阶段；本轮不提交/推送。

实际EXE图形复核：94项、18张截图、exit0、stderr空，artifacts/d059-r1/native-gpu/run-2905430；与headless同套94项，不累计成188个独立测试。协作检查92路径PASS、git diff --check exit0；root写入锁释放。

2026-11-06；来源：用户最近三项反馈。沿D058增量，不改订单/容量/点餐规则。

实际技能：C:/Users/Administrator/.codex/skills/grilling/SKILL.md 与 godot-gdscript-patterns/SKILL.md，未声明版本；已读取并执行只读事实委派/需求核查。imagegen用于补绘独立坐姿素材，原图只读。
GRILL_RESULT=ANSWERED。用户确认睡觉或主动保存，普通退出不保存；新档创建与02:00强制收尾保留安全保存。覆盖原D033/D056的隐式写盘触发，仍不支持营业/QTE现场存档。装修、库存、金钱、研究、剧情、等级等作为同一快照保存/回退；迁移只保存读入的旧档兼容结果，不捕获游玩后进度。

## 验收标准
- AC-D059-001：普通男女及已有具名食客在真实餐桌坐下，臀部接坐垫、转向同步、桌沿正确遮挡；不改变同ID订单及落座完成时点。坐标测试＋Compatibility截图目检。
- AC-D059-002：餐厅单方向输入平行对应地砖边，组合输入不加速；180px/s、Shift1.6倍和碰撞后预算不变，其他场景仍绝对方向。真实输入/碰撞及步态回归。
- AC-D059-003：睡觉/主动保存整槽；普通退出、研习、开门/普通日结、雇佣、推荐商路及小屋剧情不偷偷写盘。新档/02:00例外保留；保存失败不能当成功离开；隔离目录重启验证全部领域同步保留/回退，不触及真实存档。
- AC-D059-004：导入/加载/必要单元与真实场景测试，导出检查及图形证据记录真实数量；人工观感PENDING。

本轮工程就绪；旧D058通过未计入本轮测试数，人工观感待试玩。

## 已实现与验证过程
1. TDDinerArt新增独立斜向坐姿图集（普通男/女、阿铃、老陈），保留三衣色；FurnitureModel定义坐垫与各角色臀部锚点，旋转时同中心镜像。坐下过渡沿真实Guest位置插值，桌沿仅低处遮挡远脚，不再横穿胸口；不改订单落座确认时点。
2. KitchenPlayer把input_transform与motion_transform分开；Restaurant仅装配地砖轴输入，组合键投影后归一化。继续使用原碰撞预算和真实屏幕计步，其他世界默认identity。
3. 正式槽的研究、事件确认、商路、小屋解锁和普通经营只提交内存；Shell保留主动保存/睡觉/02:00与新档。退出/返回都有明确不保存文案及独立保存选项，写入失败留在游戏；存档格式、老档迁移和安全边界不变。音量等全局偏好仍独立保存。
4. 没有新存档框架或伪造持久化结果；QuitProbe仅替代测试进程最后的退出动作，前面的真实Shell按钮、Profile与文件写入都执行。操作系统进程关闭另由EXE启动/退出探针验证；真实玩家档未读写。

失败记录保留：d059-first在受限环境导入时无法写入锁定引擎的editor_data，检查正确失败；获准重跑后d059-authorized为14/15，坐垫独立期望值手算差0.047px，校正为实测39.08736px；d059-second为38/42，4个新存档测试使用了不存在的饰面ID，改用正式carpet。以上均不冒充通过。首轮GPU目检发现桌沿会覆盖胸口，已缩到低桌沿并复验；原图未改。

图形最终：tools/restaurant_feedback_probe.gd，50项/22图、退出码0、stderr空；真实到店/落座/同ID后厨订单及男女/阿铃/老陈两朝向图已目检，结果在artifacts/d059/gpu/。实际美术观感仍需人工试玩。

最终专项：artifacts/check/pre-export-20261106-125002，10个测试文件、57/57用例、2195断言、669.481秒，失败/跳过0、exit0；导入与脚本/场景加载均exit0。包含真实三天经营、等级奖励、存档中断/六槽隔离/整槽回退、床与小屋/港口、真实行走/碰撞/暂停/入座和后厨订单。3次既有Float/Int比较提示不影响断言，无解析/运行时错误；本轮没有重跑全部591旧用例。

首轮导出资源审计拦截新坐姿png.import，已更新显式白名单；失败摘要保留artifacts/d059/export-first-summary.json。通过777项源码/数据/资源/测试哈希核对后复用上述PASS检查，唯一后续生产代码变化是“保存校准”改为“应用校准（随进度保存）”的按钮文案，校验脚本逐字检查其余内容不变。重新运行原导出、资源清单、3次正式启动/退出及实际EXE鼠标交互，565运行资源、3×4启动检查、headless94项PASS（exit0），其中包含新图资源与退出/主动保存实际重载。一次性恢复脚本artifacts/d059/resume_export.ps1不进入发布包，不加入跳过检查开关。

本地build/TownDiner.exe与TownDiner.pck于2026-11-06 13:04:16–17更新；两者需同目录。默认重现：`pwsh -NoProfile -File tools/export.ps1 -CheckSuite restaurant-feedback`；只检查用`tools/check.ps1 -Suite restaurant-feedback`。远程CI NOT_RUN，人工连续操作/坐姿观感PENDING；下一步为本轮试玩反馈，不推进其他阶段。

实际EXE图形复核也已完成：94项PASS、exit0、stderr空，18张图位于artifacts/d059/native-gpu/run-3010516；坐姿与放弃/保存弹窗已目检。headless与GPU同94项为重复环境验证，不算188个独立用例。最终协作检查89路径PASS、git diff --check exit0；无提交/推送，原未提交成果保留，写入锁释放。

| AC | 结果 | 证据 |
| --- | --- | --- |
| 001 坐姿与落座 | PASS（工程） | 臀部坐垫坐标/旋转、真实场景流程、50项GPU/22图 |
| 002 地砖方向移动 | PASS | 8向速度与输入、162个滑墙帧、Shift/碰撞/步态回归、EXE真实输入 |
| 003 明确存档 | PASS | 4个新增整槽测试、15项旧档回归、8项等级回归、EXE鼠标保存/回退 |
| 004 检查和导出 | PASS（专项） | 57/57、565资源、3×4启动、EXE94项；人工PENDING |

## 试玩方法
1. 启动build/TownDiner.exe，餐厅分别按W/A/S/D，检查沿地砖边移动；组合键与Shift检查速度。
2. 开店看客人走到桌边坐下；留意坐垫接触、朝向和手臂/桌沿。
3. 筹备时主动保存，然后修改装修/采购或研习，返回主菜单选择不保存；重载应一起回到原记录。
4. 重做改动后选择“保存并返回主菜单”，重载应保留；睡觉和02:00按新规则自动记录安全快照。
## D073 厨师按真实工位制作（2026-11-14，ENGINEERING_READY / PLAYTEST_PENDING）
用户本轮明确：番茄炒蛋先冰箱取番茄→砧板切配→锅中投料→冰箱取鸡蛋→锅前投料/烹饪→端成品至出餐口；移动与实际操作互相约束。覆盖原D071/远端厨师只随工序标签移动的表现层实现，客人桌边收到菜才结算规则保留。

实际读取 grilling：C:/Users/Administrator/.codex/skills/grilling/SKILL.md（无版本字段）和 godot-gdscript-patterns，同目录 skills 下；前者要求的环境事实由 chef_flow_facts 只读核查。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：用户已指定顺序，其他菜按已接入的菜谱/客人备菜谱，不新增玩法决定。参数列为 AI-083 可调假设。

- AC-D073-001：真实番茄炒蛋订单，厨师逐份从冰箱取料；需要切配的原料到共享砧板执行既有真实自动输入谱，切配会话转移至已认领锅，之后取下一份。不在行走时提前切配/烹饪/出餐；验证事件轨迹、位置、库存、成品步骤。
- AC-D073-002：工位从实际 KitchenWorld.stations/bounds 导出；行走不穿设施，四向动画按真实位移、切配/烹饪/端盘表现按当前工作状态。真实渲染截图及路段几何核验，人工手感待试玩。
- AC-D073-003：营业/剧情/暂停/隐藏厨房共用现有逻辑时钟；粗细时间步、重进/取消/撤任/收夜无重复扣料或旧动作。暂停位置、朝向、动作时间与菜谱进度均不变。
- AC-D073-004：两厨师不争用同一锅/砧板；不抢玩家手中/砧板/锅内食材。玩家访问员工占用设施收到明确提示；缺料可等待，取消后的原料保留加工与到期信息；未整理工作不能边界保存。
- AC-D073-005：真实成品仅到达出餐口才存入既有 TableService，服务员/玩家原取送及评价规则保持；隔离测试、检查链、导出与本地包验证分别记实。

实现：`TDKitchenStaff`持有独立手持会话/任务与物理位置，上层ShopView装配、KitchenWorld只呈现；已有Lane/Session/BeatSheet执行切配与炒/蒸，原料转锅保留ID/切型/历史/保质期，冰箱实际拿取才扣料。员工和玩家共用物理砧板但不共用可变手持会话，锅用session_id认领；出锅后走到出餐口才排盘。四向步态由位移驱动，切配刀、翻炒锅铲、调味瓶、蒸汽和端盘为轻量占位动作，留白显示等待下一拍。旧独立开发厨房的标签动画只保留兼容测试，正式ShopView不再使用。

已发现并修复：等待砧板的零长路线导致微步循环；已有QTE到达结束边界但未完成Lane收尾，导致固定员工停在砧板；粗细时间步的温度积分仅有约1.5e-6℃误差，连续数值测试使用1e-5绝对容差，身份/顺序/库存仍精确比对。无效测试调用和营业中签约的探针错误已修正；真实EXE失焦会正常暂停，图形探针经原暂停菜单恢复，不关闭产品的失焦保护。

失败证据保留：chef-workflow-01/final 的零测试解析失败被严格入口拦截；tests-02被中断、tests-03缺料场景和tests-04严格浮点比较失败；chef-regression-01在固定员工边界卡住后主动中断（exit -1），4个诊断副本超时不是PASS。gpu-01/02及exe-gpu首轮的招聘/失焦探针失败保留；后续成功结果不能抹去这些历史。157加载检查中的VN默认资源映射警告来自独立构造StoryRunner，正式插件配置和导出资源仍另行核验。

试玩（人工PENDING）：
1. 筹备时H签约、G给主店派驻厨师，备好番茄炒蛋主料和调料，菜单开启这道菜。
2. 开门等真实客人落座，在厨房看取番茄→切配→入锅→再取鸡蛋→灶前炒菜→端盘至出餐口。
3. 到餐厅由玩家E取盘/桌边E送菜，或派驻服务员观察自动取送；出餐口阶段客人仍有耐心限制。
4. 尝试暂停、切换场景、两厨师/玩家占用砧板；重视动作可读性、等待长度及手工配合感受。
5. 仍按D059主动保存/睡觉；员工在做菜或出餐口有盘时，先完成服务或夜末整理，不能保存任意QTE现场。

范围与限制：正式主店流程已实现；用的是现有真实菜谱和自动输入，不是测试替身或固定评分假菜。没有另建分店可操作厨房、动态全屋任意家具寻路或精绘厨师职业动作图集；角色仍复用已有普通NPC素材。全仓测试/远程CI NOT_RUN，人工动作观感/双厨协作/声音待试玩，不自动推进新阶段或推送。

最终验收：AC-D073-001—005工程全部PASS，人工观感PENDING。10/10专项1352断言（55.080s，artifacts/check/pre-export-20261114-205041）与34/34相关用例512断言（526.825s，artifacts/check/chef-regression-final），合计44独立用例/1864断言，均0失败/0跳过/exit0。后者覆盖玩家真实输入、双菜鼠标、原服务员实际步行、重复送桌/超时转单/退盘/收夜、固定员工连续两单、旅行/失焦/碰撞和存档迁移；最后仅等待标签/工序工具绘制调整由最终专项与EXE图形复验。

引擎锁定4.7.2.stable.steam.ed1daf0bf、GUT9.7.1、Compatibility。导入exit0，加载157资源/0失败；导出1134运行资源，明确包含两个新增正式脚本、排除测试/原资料。build/TownDiner.exe＋TownDiner.pck于20:52更新，实际EXE启动3×4、headless交互94项PASS。最终EXE图形27项/7图、exit0，证据artifacts/chef-workflow-20261114/exe-gpu-final.log及artifacts/export/chef-probe/screenshots/report.json；已目检厨师切配/端盘/灶前和餐厅送达截图。隔离测试PCK只替换入口，所有运行资源来自正式runtime.zip，不依赖源码补文件。源工程GPU27项是重复环境验证，不累加为独立用例。

命令：`pwsh -File tools/check.ps1 -Suite chef-workflow -TimeoutSeconds 600`；相关回归`-Suite chef-regression -TimeoutSeconds 1200`；重建`pwsh -File tools/export.ps1 -CheckSuite chef-workflow -CheckTimeoutSeconds 600`。原始资料/指定素材43文件哈希一致（protected-check.json），新增文件/包校验见delivery-hashes.json；协作integrator检查500路径通过，git diff --check通过。共享写入锁释放，未提交推送，不读写真实玩家档。


## D074 — 厨房提示与餐厅信息栏（2026-11-15）

来源：用户要求“厨房提示文字看不清、餐厅左上角文字重叠”一并修复并重建EXE。复用2387a74整合后的木纹美术，不修改原图片或设计资料。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS；使用实际grilling（C:/Users/Administrator/.codex/skills/grilling/SKILL.md，未声明版本），该技能明确的只读事实调查由hud_readability_facts完成，root唯一写代码/共享文件；godot-gdscript-patterns同级SKILL已读取。没有新增产品决策，布局为ASSUMPTION AI-084。

实际实现：KitchenWorld以PanelContainer/Label/ProgressBar显示手持、锅内、工位与炖煮；显示只读取既有context/meters。提示文字不再继承暗色背景的旧配色，手持最多两行、超长省略，正常长警告完整换行；锅内容在厨房上方以免挡住人物。ShopView嵌入态将旧营业说明放到统计栏下方、任务卡右侧，隐藏重复房间标题。GameHUD/StoryGuide提供只读reserved_bottom，Shell装配RestaurantWorld.set_info_top，不增加跨场景路径或全局事件。营业信息使用有边界的ScrollContainer，保留原遮罩/装修/营业显隐，去掉重复岗位能力长串，H仍能查看完整员工信息。暂停、移动、真实送桌与经营时点不变。

验收与结果：
- AC-PHASE-4-D074-001 PASS：实际0.71875厨房缩放下检查工位名、手持/长警告、两锅与两条炖煮提示；源与正式EXE昼夜截图，木牌与文字不被夜间染暗，手持与其他文字/操作栏无重叠。
- AC-PHASE-4-D074-002 PASS：实际主场景中统计栏、短提示、任务卡与营业信息分别占位；有任务/无任务、1280×800及1600×900、长订单显示滚动且不越过底栏均通过。
- AC-PHASE-4-D074-003 PASS：5文件34用例514断言0失败/0跳过/exit0（445.825秒，hud-readability-regression），覆盖真实输入厨房、双菜、实际服务、超时转单、场景切换；4文件20用例870断言0失败/0跳过/exit0（5.68秒，pre-export-20261115-133349）。合计54独立用例1384断言，不把初轮重复20计数。源真实厨师→出餐口→服务员27项/7图，通过后最后仅调整锅提示位置；最终布局由源与最终EXE图形52项复验。
- AC-PHASE-4-D074-004 PASS：锁定Godot4.7.2.stable.steam.ed1daf0bf编辑器与4.7.2.stable.official.ed1daf0bf模板，Compatibility；158加载0失败、1248运行文件白名单、正式EXE三次启动各4检查、无图形输入/保存94项。最终EXE图形52项/7截图exit0，实际查看夜间厨房和餐厅任务/营业栏。13:34:25 EXE、13:34:27 PCK，哈希见artifacts/hud-readability-20261115/build-hashes.json。

显示压力验证使用明确标注的长文字/两锅meter数据，只测试呈现；实际开门/库存/订单沿真实Shop流程，真实员工制作与送桌另由现有chef_workflow_probe证明。不把压力样例当作正式订单或新玩法。实际EXE探针采用正式runtime.zip全部资源，只替换一次性入口；正式PCK不含工具/测试或原始资料。测试设置与存档都在artifacts隔离目录。

复现命令（PowerShell）：
1. tools/check.ps1 -Suite chef-regression -TimeoutSeconds 600（可传-GodotPath artifacts/vn-framework-20261113/engine/godot.exe绝对路径）。
2. tools/export.ps1 -CheckSuite ui-wood-core -CheckTimeoutSeconds 600（同锁定GodotPath）。
3. Godot --path F:/MyGameTBD --rendering-method gl_compatibility --script res://tools/hud_readability_probe.gd；正式包验证由tools/pack_title_probe.gd -- --hud-readability生成一次性PCK，执行脚本/日志保存在artifacts/hud-readability-20261115。

人工试玩PENDING：启动build/TownDiner.exe，进厨房查看手上/锅内提示；接单后到餐厅看左上信息；有教程任务时检查互不遮挡；切换窗口大小、滚动多订单。全仓回归/远程CI NOT_RUN，未承诺所有屏幕/DPI均已人工检视。

失败/限制如实保留：source-initial3项失败（任务遮手持及未推进营业的显示探针），修复布局并令探针走真实营业刷新后复验；gpu-initial/gpu-r1/gpu-r2及全部日志保留。加载工具单独构造插件StoryRunner仍产生默认asset-map警告，158加载无失败，正式插件沿既有配置。43原始资料/指定素材哈希一致，12:41旧包备份于before-build；root锁释放，未提交或推送，不自动扩展阶段。


### D074 合并前全量回归修复（2026-11-15）
PR #9 首轮完整 CI 发现 9 个失败用例（102 文件/808 用例，四个分片均真实运行，0 跳过）。真实运行缺陷是餐厅移出场景树后，Label 延迟尺寸通知仍查询已不存在的 viewport；`_fit_order_board` 现在拒绝已关闭/离树的回调，新增实际移除、延迟回调、重新进入的集成测试。

其余失败按已确认行为修正原有测试：具名客人必须从出餐口真实端到桌边才反馈好感；厨师时钟比较先建立独立诊断目录并检查写入成功；岗位提示沿现行精简文案；立绘允许延伸到前景对话框下方，检查头部、前景层及文本边界；开篇通过实际 VN 宿主推进 CG 并验证原生对白，而非直接驱动旧 TDDialogue 时间。系统字体测试校验同一字体资源/SimHei 首选设置，不在未安装 SimHei 的 CI 主机调用无效字体句柄。

音乐循环期望由源 WAV 的 RIFF 数据帧数独立读取，覆盖浮点 PCM 与压缩导入，不再假定已替换的旧 16/24 秒素材；实际厨房音乐的暂停、切场景静音及流引用保持照常测试。自动化不证明新曲目的听感/每拍音画同步，仍需设备试听；没有修改音乐资源或 QTE 判定。`publish-compat` 专项复用统一检查入口，完整 CI 仍运行全部测试，没有豁免、降级或移除用例。验证结果待本次修复后报告，失败日志永久保留于本地开发产物。


## D075 — 减少常驻文字提示（2026-11-15）
用户要求尽量减少文字，明显的操作不再反复说明。本轮只精简正式场景的重复说明、空状态与教程播报；保留真实订单/食材/耐心、当前任务、QTE关键按键和异常恢复路径。
GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：需求没有新的玩法、保存或输入规则分歧。实际读取 grilling（C:/Users/Administrator/.codex/skills/grilling/SKILL.md，未声明版本）及 godot-gdscript-patterns；hint_cleanup_facts 按技能要求完成只读审查，root 唯一写入。
验收先定义：
- AC-PHASE-4-D075-001：主店厨房闲置时无空手/空锅/工位名称及全局操作长栏；仅靠近目标显示所需操作键。有料、计时或失败时仍能看懂状态。真实场景截图及输入验证。
- AC-PHASE-4-D075-002：餐厅只显示实际候餐/出餐/异常信息；无重复装修分、岗位说明、送餐教程常驻栏。实际送桌和失败交互保持可用，既有集成用例与截图验证。
- AC-PHASE-4-D075-003：小镇/小屋/外镇/分店巡视无目标时不显示移动操作清单；已有任务只显示一份当前步骤，详细按键可从暂停设置查看。靠近交互、离开与重复进入验证。
- AC-PHASE-4-D075-004：缺料、失败菜、保存失败等可恢复提示与首次QTE教学保留；提示不重复永久悬挂。暂停不消耗提示展示时间；原始资料与真实存档不动。
可调呈现细节为 AI-085；本轮不提交推送，验收后停在文字密度试玩反馈点。

### D075 实现与验收
实际接入正式Shell：厨房工位仅近距离显示动作，空手/空锅/静态名称隐藏；必要持物、锅内材料与蒸制计时保持。正常取放不刷成功消息，异常短消息显示4秒、暂停冻结，同一失败再次操作仍会显示。餐厅只保留当前客流/订单/持盘/缺料状态，清掉装修分、岗位、送餐说明等重复常驻行。小镇、外镇、小屋及分店巡视仅在靠近交互目标时显示短按键提示；任务卡只留当前一步，QTE首次教学、失败菜原因、保存/退出警告保持。暂停设置和任务教学手册保留详细操作。

关键文件：`src/world/kitchen_world.gd`、`src/business/shop_view.gd`、`src/kitchen/full_kitchen.gd`、`src/restaurant/restaurant_world.gd`、`src/story/story_guide.gd`，其余场景与Shell只改对应文字呈现。没有新增美术、演示替身、存档字段或玩法逻辑。

验证均使用锁定Godot4.7.2/同提交导出模板与隔离目录：
- `tools/check.ps1 -GodotPath artifacts/vn-framework-20261113/engine/godot.exe -Suite quiet-hud -TimeoutSeconds 1200 -ReportName quiet-hud-regression`：75/75、3038断言，导入/158加载/测试全部exit0、0跳过。厨师实物流程、实际送桌、剧情试做/失败恢复、旅行与分店巡视沿原集成检查。
- `tools/export.ps1 -GodotPath artifacts/vn-framework-20261113/engine/godot.exe -CheckSuite ui-wood-core -CheckTimeoutSeconds 600`：20/20、870断言；与上组按用例ID去重共83项/3703断言，不能相加成95项。1248运行资源白名单、EXE三次启动各4检查、无图形交互94项均exit0。
- `tools/hud_readability_probe.gd` 通过真实Shell与E/F输入检查冰箱、空锅错误、重复失败、暂停恢复及场景切换；源工程和基于最终运行包的实际EXE Compatibility各81项、10截图，failures=0/exit0。实际EXE探针由`tools/pack_title_probe.gd -- --hud-readability`构建一次性包，正式PCK不含测试入口。长订单/长提示、已解锁小屋只作为显示压力配置，不冒称完整故事或经营验收。
- AC-PHASE-4-D075-001至004工程验证PASS。原34份未提交资料/罗厄文件字节一致；所有权检查与diff检查通过。源首轮81项中2个旧遮挡断言误算已隐藏标签，失败日志/截图保留于`artifacts/quiet-hud-20261115/source-initial*`与`gpu-initial/`；修正可见性条件后源和EXE通过。资源检查原有VN裸加载路径WARNING保留，运行宿主配置不变；无解析/运行错误。

本地包：`build/TownDiner.exe`（18:06:58）与同目录`TownDiner.pck`（18:07:00）。最终日志、截图、哈希回执位于`artifacts/quiet-hud-20261115/`，上一包保留在其`before-build/`。本轮全仓/远程CI未运行；连续新手教学、提示时间/文字密度人工体验PENDING。本轮不推送，停在当前增量检查点。

试玩（人工待执行）：1）启动EXE进入厨房，空手站在中央查看留白；2）靠近冰箱/砧板/锅，看短按键并取放材料；3）空锅按F，确认错误能看清且自动消失；4）做菜、放出餐口并送桌，确认订单和当前任务仍够用；5）在小镇/小屋移动，按Esc→设置查详细按键，反馈还有哪些提示多余或缺失。
