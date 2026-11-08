# D059 餐厅体验反馈

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
