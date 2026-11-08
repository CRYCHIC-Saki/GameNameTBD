# GameNameTBD · 小镇食堂

最新本地版（2026-11-08 19:36）：分店筹建现在使用五镇世界地图。进入“分店→筹建新分店”，点镇放大，左键框选，中键拖动，滚轮缩放，再选店长确认。海外开店不要求先开进口商路；菜系、合法用地、资金与主动保存规则保持。Windows运行 `build/TownDiner.exe`（PCK同目录）；检查 `pwsh -File tools/check.ps1 -Suite branch-core`，地图回归 `-Suite travel-core`。31独立用例与实际EXE图形53项通过，人工试玩待确认；完整记录见 docs/phases/branch-expansion.md D062。

## 世界地图与四镇旅行（D061-R1）
港口附近按E免费前往四镇。WASD移动、Shift疾跑；M打开五镇世界地图，滚轮缩放、按住鼠标拖动，双击小镇放大，M/Esc返回。日本为海岛、欧洲为河谷、东南亚为河网三角洲、墨西哥为高原峡谷。
旧存档首次载入会保留迁移前备份；主镇位置不变，外镇已有分店保留面积、产权与经营进度。存档仍只在睡觉/主动保存及既定安全边界写入。
检查：`pwsh -NoProfile -File tools/check.ps1 -Suite travel`；经济回归`-Suite commerce`；构建`pwsh -NoProfile -File tools/export.ps1 -CheckSuite travel-core`。本地程序`build/TownDiner.exe`与同目录PCK一起使用。详见docs/phases/world-travel.md的最新R1证据。

D061 五镇旅行：靠近港口按E，选择日本/欧洲/东南亚/墨西哥小镇，即时免费往返。按M查看当前位置与港口，M或Esc关闭；旅行不自动开放菜系或采购商路。营业可外出，已雇厨师负责真实耗料做菜，服务员/传菜及收银按岗位工作，缺岗/缺料会等待或超时。保存仍须主动保存或睡觉，读档回床边/港口。
检查：`pwsh -NoProfile -File tools/check.ps1 -Suite travel-core`；相关回归用`-Suite travel`。构建：`pwsh -NoProfile -File tools/export.ps1 -CheckSuite travel-core`。

D060 分店：筹备/打烊后到营业牌或食堂账本选择“分店”→“筹建新分店”，选菜系、左键拖出临路矩形、下一步选店长，确认后明日起营业。本镇可以多店；外镇只有已开放的合作镇可选。地图分店建筑附近也可按E查看。
菜单/价格/每日采购预算由玩家调整，店长带基础班组自动买料经营；日账分别显示采购、耗料、工资、租金、水电、利润税与欠费。同镇店铺共享有限客源，可能亏损。星级和建议费用见 `content/branches.json`，实际长期平衡待试玩。
分店与原有进度同槽保存，开办或修改预算不自动保存。专项：`pwsh -NoProfile -File tools/check.ps1 -Suite branches`；构建：`pwsh -NoProfile -File tools/export.ps1 -CheckSuite branches`。本轮过程及真实结果见[分店报告](docs/phases/branch-expansion.md)。

D059：餐厅WASD沿地砖两条斜轴移动，组合按键不加速，Shift仍疾跑；普通男女、阿铃和老陈使用对齐坐垫的斜向坐姿。
**存档：睡觉或主动“保存进度／保存并退出”才保留整份进度；普通退出不自动保存。** 未保存的装修、金钱、库存、研习与任务一同回退。新档与凌晨02:00保留安全保存；营业中或厨房尚有食物仍不能现场保存。解锁小屋前读档回港口，之后回床边。
本轮专项：`pwsh -NoProfile -File tools/check.ps1 -Suite restaurant-feedback`；构建：`pwsh -NoProfile -File tools/export.ps1 -CheckSuite restaurant-feedback`。实际结果见[本轮报告](docs/phases/restaurant-feedback.md)，人工观感待试玩。

D058 食客：开店后客人会自动沿过道走到空座、坐下并点单，后厨此时才显示同一位客人的订单并开始计算等餐耐心。满座先等位，不必按E迎宾；E仍可询问口味，传菜/收银沿用原规则。普通食客为男女各一形象、各三套衣色，带四向行走和坐姿。切到厨房不会停止前厅活动，暂停会冻结。
专项检查：`pwsh -NoProfile -File tools/check.ps1 -Suite diners`；本地完整检查与构建：`pwsh -NoProfile -File tools/export.ps1`。实际图形验证脚本为`tools/diner_probe.gd`，在锁定Godot的图形模式运行，截图写入`artifacts/diner-flow/gpu/`；测试使用隔离目录，不打开玩家存档。验收见[食客流程](docs/phases/diner-flow.md)。

D057-R2 餐厅装修：筹备或日结后，靠近餐厅内的**装修图板按E**。底部分地面/墙壁/陈设/餐桌/座椅/服务台；**点地板或墙纸卡片，立即替换整屋对应表面**。家具卡片显示半透明预览及占地，滚轮预转向，左键放下。**按住已摆家具拖动，松开放下**；选中框左上叉号删除，右上图标逆时针90°旋转，餐桌图像保持在原占地中心。右键取消、非法落点保留原位；移除方向按钮和风格/档次两栏。完成布置恢复走动，沿原合法边界存档保存。
专项：`pwsh -NoProfile -File tools/check.ps1 -Suite decoration`；专项构建与EXE验证：`pwsh -NoProfile -File tools/export.ps1 -CheckSuite decoration`。默认不传CheckSuite仍先跑全量。报告见[decoration-ui.md](docs/phases/decoration-ui.md)。

本轮新增：**开始游戏**占用空槽从港口开场；**继续游戏**读取最近进度。载入页可确认删除（本机保留归档，满六槽不会覆盖）。新档首日营业打烊后，出店跟随阿铃前往小屋；凌晨02:00会提前安排落脚，未完教学保留。解锁前读档回港口，解锁后回床边；旧档原有住所保留。新增落脚故事与CG/小屋画面见 `docs/phases/story-expansion.md` 的 D056。
验证入口：`pwsh -NoProfile -File tools/check.ps1 -Suite homecoming`。本地完整构建：`pwsh -NoProfile -File tools/export.ps1`。测试不操作真实存档；新剧情文本为本轮授权扩写，原剧本不改。


## 海港开篇预览（D054）
新建空槽会先播放抵达海港的开场，初遇对白结束后进入港口地图；已有存档继续从小屋读取。独立预览可打开 `src/story/arrival_preview.tscn` 后F6，或锁定Godot运行该场景；时间轴在 `src/story/arrival_cutscene.tscn` 的AnimationPlayer中编辑。专项：`pwsh -NoProfile -File tools/check.ps1 -Suite arrival-coast`。资源绑定和动作限制见 `assets/story/arrival-bindings.md`，工程结果见 `docs/phases/story-expansion.md`。


D053：序章使用三位角色的六种情绪/专用动作与分层CG。**J**打开任务与操作手册，**T**切换地面引路，**B**查番茄炒蛋做法；跟随阿铃时落后她会停下等你。不开门即可完成试做，必须E端菜送到出餐台后才进入真实评价。第一次QTE会暂停讲解，失误仍能继续剧情。已完成旧档可在J中回顾，无重复奖励。试玩与来源见[story-expansion.md](docs/phases/story-expansion.md)，专项 `pwsh -File tools/check.ps1 -Suite story-expansion`，完整构建 `pwsh -File tools/export.ps1`。

D054覆盖旧河道港口位置：河口港现位于小镇东部海岸，沿公共道路抵达海边栈桥，靠近候船棚按E。新档演出后从这里开始；跨镇乘船仍等待后续剧情/目的地开放，客运和食材货运分别管理。

D052：取消房屋、商铺和居民区整片土色底板，草地连续衔接，保留建筑自带台阶与内院。复验 `pwsh -File tools/check.ps1 -Suite residential`，范围及实机证据见docs/phases/town-polish.md D052。

D051：小镇采用石板路和正交正面青瓦建筑，NPC有按真实移动推进的四向步态；餐厅通道更宽、镜头跟随人物，菜谱/装修等改为分散的墙挂物，账本在真实收银台上。专项 `pwsh -File tools/check.ps1 -Suite visual-unity`，完整构建仍 `pwsh -File tools/export.ps1`。范围、图形记录及人工待验收见docs/phases/town-polish.md D051；完整素材提示见assets/town/visual-unity-v3-generation.json。

D050居民区：食堂西北、玩家小屋附近的“青瓦巷”有沿街民居和封闭小院，靠近青瓦民居/竹庭人家按E查看告示。小屋仍是个人休息和保存处。专项检查 `pwsh -File tools/check.ps1 -Suite residential`；完整Windows打包 `pwsh -File tools/export.ps1`；范围与实测见docs/phases/town-polish.md D050。住宅素材和完整生成提示见assets/town/residential-houses-v1-generation.json。

D049地图/NPC/周边交互修正：专项命令 `pwsh -File tools/check.ps1 -Suite town-polish`，完整检查 `pwsh -File tools/check.ps1`，本地Windows打包 `pwsh -File tools/export.ps1`。Godot版本仍依dependencies.lock.json，启动src/app/main.tscn或build/TownDiner.exe；近期范围/人工试玩见docs/phases/town-polish.md。

本轮D048更新：附近建筑按E交互，地图扩为宽路中式街区；客流以早餐/午餐/晚餐为主，营业持续至主动打烊或02:00。菜单牌可查看开门后剩余时段预估。旧档首次读取会先备份再迁入新地图。开发验证入口：`pwsh -File tools/check.ps1 -Suite town-renewal`；完整检查与Windows导出仍使用`pwsh -File tools/export.ps1`。验收与试玩说明见[小镇更新](docs/phases/town-renewal.md)。


D047：林夏已移除，普通食客与常驻人物分开。阿铃、老陈按全天时间活动，完成每日闲聊或真实用餐会改变好感；剧情采用双立绘，日常聊天保留原布局。08:00起，现实1秒推进游戏1分钟；02:00自动收摊回小屋，原料/切配品冷藏，已开火食品报废，床上进入次日。专项检查：`pwsh -File tools/check.ps1 -Suite characters`；本地构建：`pwsh -File tools/export.ps1`；报告与5步试玩见 [characters.md](docs/phases/characters.md)。

D046：不开店也可在原厨房做菜。老陈赠料改为可用的一份番茄炒蛋材料，旧微量礼包自动补差一次；阿铃和老陈使用素材库指定人物。开门、打烊不清空锅料；保存/睡觉前先归还原料、出餐或清理成品，不保存QTE现场。专项：`pwsh -File tools/check.ps1 -Suite story`；标准构建：`pwsh -File tools/export.ps1`。从新档跟阿铃找到老陈，结束尝羹/拒绝对话，直接回厨房不开门做番茄炒蛋，再去找阿铃。详细验收与缺失素材见 [story-kitchen.md](docs/phases/story-kitchen.md)。

新增D040主角：小镇、餐厅、厨房和小屋使用指定的火焰发色厨师形象，四向迈步与实际移动同步，松键或撞墙回站姿。R1放大厨房/小镇角色；R2修复餐厅非正交投影重复计距造成的动画快放，实际走速保持。专项：`pwsh -File tools/check.ps1 -Suite protagonist`；真实图形预览：用锁定Godot运行 `--path . --script res://tools/protagonist_probe.gd`，结果写入artifacts/protagonist-stride-r2，使用隔离存档。素材及补帧提示见 [主角素材](assets/characters/protagonist/README.md)，验收见 [protagonist.md](docs/phases/protagonist.md)。

本次 D039：修复餐厅穿墙与斜向速度，角色四向转身并面向建筑交互；新增独立小屋，日结到床休息和保存，后续读档回床边；三首休闲/营业/做菜BGM替换持续节拍器。详见 [本次验收与试玩](docs/phases/habitat.md)。专项：`pwsh -File tools/check.ps1 -Suite habitat`。

新增 **D037库存与熟练制作**：市场/工厂只出售已解锁可制作菜谱的主料，调料全部开放，按瓶/袋购买。冰箱仅展示持有库存，沿用工厂四类并显示图标、余量和保质期；到期损耗记账，切配退回保留到期日。M6长按按实际用量扣调料，耗尽时变灰禁用。手工制作分≥80按实际分累积，达到400后装好锅料按F可选自动制作，完成后E端盘；自动仍耗料、占锅、耗时，不增加手艺。QTE与评分容差已放宽，建议数值待试玩。验证和五步试玩见 [kitchen-stock.md](docs/phases/kitchen-stock.md)。专项：`pwsh -File tools/check.ps1 -Suite stock`，真实厨房：`-Suite service`，完整导出：`pwsh -File tools/export.ps1`。

当前入口已更新为 **D033：单店游戏流程与六槽存档**。主菜单为“开始游戏 / 继续游戏 / 载入存档 / 设置 / 退出游戏”，新档出生顺序已由D054更新为先播港口开篇、再进入海港地图。完整 Phase 4 未完成；本轮验收、失败记录与人工待测见 [game-shell.md](docs/phases/game-shell.md)。

新增 **D036五镇社会经济**：成都、巴黎、东京、曼谷、墨西哥城对应菜谱树五菜系；新档只开本地商路，其余等剧情推荐接口。320家庭实际领薪、消费、储蓄，店铺收款有家庭付款方；正利润缴税，亏损不缴利润税。商业街的钱庄可按E办理存取/限额贷款，账本分开本金、利息和税费。NPC在商业街挂牌地块投资、施工、开分店，不拆住房或占玩家/工厂用地。旧13镇存档显式迁移，已付货运保留，旧日不追税。数值仍待人工试玩；范围与验证见 [world-economy.md](docs/phases/world-economy.md)。

专项检查：`pwsh -File tools/check.ps1 -Suite commerce`；真实游戏流程：`pwsh -File tools/check.ps1 -Suite game`。长期模拟：锁定Godot运行 `--headless --path . --script res://tools/economy_simulate.gd`，结果写artifacts/society-simulation，不接触玩家档。

### 当前版本五步试玩

1. 点“开始游戏”直接进最近存档；没有存档时自动新建。另开一档使用“载入存档→新建存档”，选空槽并命名。WASD移动，靠近食堂门口按E进入；餐厅后方门按E到厨房，厨房下方门按E返回。
2. 开店前沿路到菜摊按E买食材，现货立即进入冰箱库存。首轮建议番茄/鸡蛋各4份，油/酱油各1瓶，盐/糖/淀粉各1袋；份量只是试玩备货建议。菜摊显示今日预计客流。
3. 回店与“营业牌”按E交互，勾选当天菜品、调整售价后开门。进入厨房复用既有备菜与QTE：E取放、F开灶、Q取锅料。订单自动排队，按成品匹配交付。营业中不能离店采购。
4. B或餐厅菜谱架打开研习。新档只有蛋炒饭、番茄炒蛋；阳春面和蒸水蛋使用真实厨房操作研习。花灵感买永久资格，80分解锁，失败可免费重试；营业中只能查阅。
5. 营业牌可提前打烊；处理完余单，去“账本”查看日结/保存，离店后去店对面“小屋”，面向床按E休息、保存并进入次日。Esc暂停菜单也可在筹备/日结保存。退出营业会明确提示回退最近边界，不能恢复QTE现场。

存档在 `%APPDATA%/TownDinerPhase0/profiles/slot-01.json` 至 `slot-06.json`：经营、研究、世界和装修写在同一校验包。新档互不继承；在新游戏存档页点“导入旧进度”才会只读导入旧 `shop-v1.json` / `research-v1.json`，源文件保留。坏档/未来版本不会被静默覆盖，可明确恢复已校验备份或临时档。

钱庄在商业街内部，走到“钱庄”牌前按E；存取借还随当前槽保存。商业街的施工商铺和街坊食堂也可近前按E查看经营告示。五镇经济已相互联动，其他四镇当前只在后台模拟，不代表它们的旅行场景或剧情已经完成。

反引号 **\`** 打开控制台，输入 `debug` 后可用 `help`、`status`、`san 0..100`、`tools`、`debug_off`。旧厨房/营业/员工/分店试验在独立调试入口，不与玩家槽混用。进入旧工具需先打烊并保存。

新档首次出生在店门外；后续载入回小屋床边。WASD按屏幕方向走动，斜向同速；按住左右Shift疾跑（1.6倍），松开恢复步行；面向建筑/工作台按E，停止后保留朝向。筹备时床可保存，日结后可过夜，营业中不能离店。休闲、营业、做菜三首BGM随状态切换。

设置支持主音量、全屏/窗口和当前槽研习输入偏移。新的街景、家具图集见 [素材来源](assets/town/README.md)；实际键鼠、音频延迟和连续营业疲劳仍需人工试玩。

```powershell
# 已配置GODOT_BIN，或使用本机dependencies.lock.json路径
& 'E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' --path 'F:/MyGameTBD'
pwsh -File tools/check.ps1 -Suite profiles
pwsh -File tools/check.ps1 -Suite game
pwsh -File tools/check.ps1 -Suite title
pwsh -File tools/check.ps1 -Suite movement
pwsh -File tools/check.ps1
pwsh -File tools/export.ps1
```

统一检查默认每个进程上限1200秒；超过上限仍失败，零测试/跳过/解析错误仍失败。CI继续调用同一入口，本轮远程CI未运行。导出后的 `build/TownDiner.exe` 与同目录PCK一起使用。测试、导出检查使用隔离目录，不操作玩家档。

---

### 历史入口与原型说明

以下是旧开发阶段的操作记录；“新开店 / 继续经营 / 走进小镇 / 布置餐厅”等旧菜单仅在独立调试入口可见。初始解锁、保存位置及正常试玩步骤以本页上方 D033 和 D030–D032 最新决定为准，不把旧五菜初始或Perfect解锁当当前规则。

当前为D030菜谱研习增量，覆盖下文历史D020的初始五菜/Perfect直接解锁规则。新研习进度从**蛋炒饭、番茄炒蛋**开始，旧营业档已合法学会的菜通过“继续经营”保留。图谱按参考HTML呈现5个菜系、100节点；本轮开放**阳春面、蒸水蛋**两张研习谱。其他菜系等待剧情推荐接口，未配谱面的节点不扣灵感。完整Phase4仍未完成。

研习试玩（5步）：

1. 启动后点“菜谱研习”，或在游戏内按 **B** 打开，浏览中餐树，选“阳春面”或“蒸水蛋”。搜索、缩放、定位和前置按钮可用。
2. 花1点灵感购买该菜永久研习资格，开始谱面。使用厨房原有操作：空格点火/上笼/出锅、鼠标控温和调料长按，工序自动推进；看Perfect/Good/Miss反馈。
3. 达到80分解锁；失败结果页点“立即免费重试”，不耗食材、不重复扣灵感。D032暂取消研习每日时间额度与耗时，旧进度时间用尽也可重试。Esc/失焦暂停，判定偏移可在图谱详情校准。
4. 按B或“返回”原地继续，当前筹备菜单立即加入新学菜。查看书会主动暂停当前场景；营业中只能查看，打烊后才能研习。未解锁菜系显示锁且不可进入。蛋炒饭用熟米饭+鸡蛋，阳春面用细面条+清水走灶台煮制，蒸水蛋用鸡蛋+清水走蒸笼；参数为建议值。已覆盖真实制作和交付。
5. 重开游戏检查资格、最佳分与解锁仍在。正常存储在user://research-v1.json；坏档会显示恢复入口，未来版本拒绝覆盖。真人设备延迟、音画同步和谱面乐趣均待试玩。

专项检查：`pwsh -File tools/check.ps1 -Suite research`；全量检查：`pwsh -File tools/check.ps1`（单阶段超时预算1800秒，覆盖扩大的完整回归）；本地导出：`pwsh -File tools/export.ps1`。锁定Godot/GUT版本继续由dependencies.lock.json规定，未升级。图形检查工具：`tools/research_visual_check.gd`，所有验证存档隔离在artifacts/test-storage。

接口、建议参数和逐项证据见[研习验收记录](docs/phases/recipe-study.md)、[契约D030](docs/CONTRACTS.md)。下面保留历史经营说明；涉及解锁的旧规则以本节为准。

历史Phase 2单店连续营业说明。工程仓库：[GitHub](https://github.com/CRYCHIC-Saki/GameNameTBD)。本轮远程CI未运行，未自动提交或推送。

已打通采购备货 → 菜单定价 → 自动来客 → 真实取料/备菜/烹饪/端盘 → 评价和日结 → 次日 → 保存继续。首批5道菜：番茄炒蛋、干炒牛河、麻婆豆腐、宫保鸡丁、辣椒炒肉。复用D015/D016像素厨房、五类QTE与菜谱打谱；没有重建做菜系统。新增数值为PROPOSED，画面和音轨仍为原型，人工玩法验收待完成。

## 五步试玩

本地双击 `build/TownDiner.exe`，保留同目录 `TownDiner.pck`。仓库不包含导出包；克隆后用下方启动/导出命令。

1. 选“新开一间店”，先只上架番茄炒蛋，保留参考价。先看当天预计访客范围，点“补齐”，再点三次“再备1份”准备四份；点“开门营业”。
2. 客人自动排队，无需接单。WASD/方向键走到大冰箱，E打开取料：拿番茄，到砧板E放下，再选“大块/小丁/薄片/长条”开始按谱备菜，完成后砧板E取走、任一灶台E放入；再从冰箱拿鸡蛋放入同一锅。
3. 对有食材的灶台F开始自动做菜。按显示的方向键/空格、鼠标火候条及调料环完成每段；M6到拍点后左键按住相应调料，到目标时长/用量松开，按住越久实际添加越多，不用同时控温。出锅先看预告，出现提示后按住空格约2秒，到绿区松开。Esc暂停，失焦自动暂停。
4. 灶台E端菜，右下出餐台E交付，读主要扣分原因。不同菜可乱序提交，同菜优先先到的客人。另一口锅可独立加工；确实缺料的订单自动谢客并小幅扣人气，售罄菜不再被新客点单。
5. 日结核对收支/库存和反馈，可命名保存这份做法。点“准备下一天”，调整上架菜、备货和售价，自建菜也可上架。重复经营3天，再保存并从主菜单“继续经营”检查日期与库存。

营业默认6分钟、顾客耐心4分钟，到点停止接客后处理余单。看账本/冰箱弹窗不会停营业；主动暂停才冻结。拿取材料或提交调料时扣实际用量，搬运不重复扣料；交付时收款。客人超时保留已有食材/成品，可供给后来的同菜订单。应急补助只在次日起筹备阶段确实买不起最便宜补货时可领取，每天一次。

甜口与咸鲜口属于同一种菜。切型由玩家选择：大块2刀，小丁6刀加2次转向；最早同菜客人的口味要求改变调味谱，多糖需要更长的糖料长按。实际少切/少倒/多倒仍会改变成品和评价，数值均为建议值。自建方案保留名称、版本和实际用量；明确的顾客要求会叠加到该做法上。

自建菜保存食材与完整自动工序方案，不保存分数；改名保留ID，下次仍需真实按谱。未完成备菜、缺调味等方案会说明原因并拒绝保存。当前支持已审核五道炒菜及汽锅鸡的完整方案，不含自由工序编辑器。

## 自由备菜与取回

- 三单同时等待，卡片写明材料。建议来客基数45秒，库存足够才接后续订单；初始预估6—10人。
- E取放/端盘；F打开锅或蒸笼开始自动流程；Q查看并取出锅内一份材料。右锅与蒸笼共用同一个槽位。
- 手拿食材回冰箱按E退回，已切配结果保留，冰箱单独显示冷藏食材。开火后不能拆回原料，可继续做或到垃圾桶清理整锅。
- 不需要对应订单也能切、炒、蒸。锅里实际材料和炒/蒸方法匹配菜谱，顾客不会禁止备菜；菜板切型选错也能继续，交付时按要求评分。
- 汽锅鸡初始未解锁：鸡肉+菌菇入蒸笼，按F照谱做；材料/工序齐全且每个计分工序Perfect即可提前解锁。初始五道炒菜保持已解锁。
- 数据库外的组合经历完整过程，自由长按调味后得到“失败的菜品”；端到垃圾桶E丢弃。误交出餐台会送给队首客人，差评并降人气，不能保存成菜谱。

## 保存与恢复

仅筹备和日结能保存；开门前自动保存筹备，准备下一天前保存日结。营业中退出会回到最近边界，不能恢复顾客队列或QTE；返回和关闭窗口都会提示。筹备或日结的后续修改请点“保存进度”。

当前Windows存档：`%APPDATA%/TownDinerPhase0/shop-v1.json`，保留既有用户目录。写入有校验、临时文件和上一份有效备份；坏档不静默覆盖，继续页面可明确选择恢复已校验备份/临时文件。未知版本不降级覆盖。新开店首次保存前会确认并保留旧档。测试只使用 `artifacts/test-storage`。

## 小镇与斜角餐厅

主菜单「走进小镇」沿十字路走，E 查看市场、竞品和功能区。关掉一个功能区，当天客流人数、预算和外来饮食偏好会变。「布置餐厅」是斜角房间：地面加两面墙，方桌画成菱形。雇用迎宾和收银会从现金里付工资；下一天再扣租金、水电和设备维护。点「全程来客」。菜单外的菜可以拒绝；接下并上菜后，总体评价达到 60 会记入这套客流菜谱。点「去厨房」后，在原来的营业厨房里按谱做这道菜。客流面板能看到预算分布、选店结果、装修效果、开支和到货。「备料」可以按一道菜一次买齐原料，也可以点选一种食材；冷藏、冷冻和干藏会延长保质期。这套账用元，不写入原来的营业存档。

Kenney 素材先检索再下载，不要把付费合集当免费包：

```powershell
python tools/kenney_fetch.py search --query furniture
python tools/kenney_fetch.py download --query furniture --out artifacts/kenney --limit 3
```

## 三人协作

正式规范见 [协作手册](docs/collaboration/README.md)。2026-10-24确认当前三条线为建筑（building）、原料厂商（supplier）、小镇经济（town-economy）；每波由其中一人轮值集成。手册第0节包含每日操作、共享文件重叠处理、状态归属和GitHub保护建议；旧cook/economy/town分支保留兼容。

```powershell
# 校验三人目录所有权配置
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Validate

# 查看示例波次next的三条新工作线（不会创建分支）
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Status -Phase 4 -Wave next

# 基线提交且工作区干净后，先预演创建四个工作树
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Init -Phase 4 -Wave next -BaseRef origin/main -WhatIf

# 角色分支检查自己的未提交文件
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Check -Role supplier `
  -BaseRef origin/integration/phase-4-wave-next -TargetBranch integration/phase-4-wave-next -IncludeWorkingTree
```

上方next是示例名称，新波次以CURRENT_WAVE登记的名称和active_roles为准。协作工具兼容Windows PowerShell 5.1，CI使用pwsh；`pwsh -File tools/test_collab.ps1`可在隔离Git仓库验证越界、共享文件和分支规则。当前D033 PR #2尚未合并，先审查确认共同基线再初始化新波次。Init只在干净工作区执行，不提交、推送或创建PR；其他开发者使用各自clone即可。

## 工程运行

已锁定 Godot 4.7.2 stable、静态类型 GDScript、Compatibility、GUT 9.7.1。当前机器 Godot 在 Steam 安装目录，未修改全局环境；准确路径、版本与校验值见 `dependencies.lock.json`。命令需要 PowerShell 7.2+，本机实测7.6.5。

在项目目录运行：

```powershell
pwsh -NoProfile -File tools/run.ps1
pwsh -NoProfile -File tools/run.ps1 -FullKitchen
pwsh -NoProfile -File tools/run.ps1 -Cooking
pwsh -NoProfile -File tools/run.ps1 -Module
pwsh -NoProfile -File tools/check.ps1
pwsh -NoProfile -File tools/check.ps1 -Suite business
pwsh -NoProfile -File tools/check.ps1 -Suite service
pwsh -NoProfile -File tools/check.ps1 -Suite cooking
pwsh -NoProfile -File tools/check.ps1 -Suite scoring
pwsh -NoProfile -File tools/verify_gate.ps1
pwsh -NoProfile -File tools/export.ps1
```

其他机器先安装同版引擎与导出模板，通过 `-GodotPath '完整路径'` 或 `GODOT_BIN` 传入。GUT源码已随项目放在addons/gut，含MIT许可证，不需要额外全局插件。检查入口拒绝引擎版本漂移；当前Steam可执行文件还验证完整版本和SHA256。Steam若自动升级，需要恢复锁定版或明确批准版本迁移，不能静默升级。

Godot编辑器导入根目录 `project.godot` 可运行主场景；完整厨房独立入口为 `dev/full_cooking_test.tscn`，旧原型为 `dev/cooking_test.tscn`，Phase0探针为 `dev/module_test.tscn`。独立测试见 `docs/COLLABORATION.md`。

## 检查与证据

检查链：引擎/依赖锁定 → 资源导入 → 生产脚本/场景加载 → GUT契约/单元/集成。日志和JUnit/summary写入 `artifacts/check/<run>/`。检查数量必须等于发现数量且大于零，失败/跳过/解析错误/超时一律非零退出。

`verify_gate.ps1` 在artifacts下创建新的中文空格路径副本，依次证明正常、故意失败、必测跳过、解析失败、零测试、恢复正常的退出码。不会改写原工程。副本与测试输出被Git忽略，删除时只能删除明确确认的artifacts目录。

`export.ps1` 先执行同一检查入口，再导出Windows包、核验资源白名单并执行无界面启动。随后用实际导出的Windows程序和资源创建隔离验证包，通过鼠标按下/松开检查空档创建、最近存档及指定槽载入；不完成检查或任一错误都失败。验证入口不写入交付包。导出不含GUT、测试、原始设计资料、独立模块入口和工具脚本；本包明确为开发演示，旧兼容依赖尚随代码打包但不从菜单暴露。

运行食材索引为`content/ingredient_index.json`，只提取原始资料的身份/显示字段。`tools/build_ingredient_index.ps1`可重建，统一检查会验证其与只读来源一致；不会把原始设计文档打入游戏包。

CI配置在 `.github/workflows/check.yml`，推送和Pull Request调用同一 `tools/check.ps1`。每次提交的远程结果及日志见 [GitHub Actions](https://github.com/CRYCHIC-Saki/GameNameTBD/actions)，本地通过不代替远程通过。

## 文档入口

经营等级：餐厅账本→“经营等级”查看经验、当日来源和升级奖励；日结升级自动发灵感，保存后显示奖励页。正式经验只读店铺净利润、人气和知名度，不读菜品名气。专项检查 `pwsh -NoProfile -File tools/check.ps1 -Suite progression`；图形探针 `Godot --path . --script res://tools/level_visual_check.gd`。等级同六槽存档保存，旧档从接入后开始积累；详见 `docs/phases/level-progression.md`。

- `AGENTS.md` / `docs/DEVELOPMENT_PROTOCOL.md`：总控规范，之后每阶段必读。
- `docs/PROJECT_STATE.md` / `docs/DECISIONS.md`：当前状态、已确认决定、建议与冲突。
- `docs/ARCHITECTURE.md` / `docs/CONTRACTS.md`：模块职责、状态所有权和公共接口。
- `docs/COLLABORATION.md`：目录归属、共享文件负责人、独立检查与接口变更。
- `docs/collaboration/README.md` / `collaboration.config.json`：三人协作规范和机器可读所有权。
- `docs/phases/phase-0.md`：AC与实际验收证据。
- `docs/phases/phase-1.md`：完整系统AC与实际证据；旧76项验收保留历史。
- `docs/systems/cooking.md`：当前v3接口、建议参数、数据扩展与外部接入；PHASE1_INTERFACES.md为旧v2原型。
- `docs/phases/phase-2.md` / `docs/systems/business.md`：单店营业验收、内容来源、规则与建议值。
- `docs/ROADMAP.md`：当前检查点与后续里程碑。
- `docs/SOURCES.md`：原始资料索引与指纹。原始文件保留在 `doc/source/`。

工程与玩家验收分开：最新本地检查证据见docs/PROJECT_STATE.md；真实键鼠/耳机同步、反馈可理解性与好玩程度仍待人工试玩。当前仅完成已授权的Phase4切片，协作配置不代表新功能阶段开工。

### D053-R2 连续演出

剧本演出自动全屏播放，普通点击/长按不会跳镜头；右上角可暂停或只跳本段，普通对白仍点击阅读。新档从阿铃序章体验，已完成旧档可J回顾（不重复奖励）。实际录制预览：`artifacts/cg-revision/preview.html`，102秒无声录制；游戏内有拟音，正式角色配音未制作。专项复查：`pwsh -NoProfile -File tools/check.ps1 -Suite story-expansion`；完整检查及导出：`pwsh -NoProfile -File tools/export.ps1`。


### D055 序章试玩修正

新档在开篇输入昵称前显示“？？？”；跟随阿铃走正门，靠近老陈食材铺门口按E。教程番茄/鸡蛋用尽可在冰箱免费重领，已取出/切好的食材优先使用；用同一炒锅放入两种主料后按F，完成后E端盘、到出餐台E交付。交付后停止补给，余料回普通库存。

专项检查：`pwsh -NoProfile -File tools/check.ps1 -Suite story-fixes`；实际图形核查：锁定Godot `--path . --script res://tools/story_playtest_probe.gd`（使用artifacts下隔离槽）；完整检查与导出沿用 `tools/export.ps1`。
