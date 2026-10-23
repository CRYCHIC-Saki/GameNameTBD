# Phase 4 增量：统一游戏流程与多存档

2026-10-23；入口反馈修正ENGINEERING_READY / PLAYTEST_PENDING，DELIVERED_LOCAL；仅用户本次授权范围，不自动执行其他 Phase 4。下方原交付数据保留历史，最新证据以文末修正记录为准。

## 来源与决定

- D033：主菜单仅开始、继续、载入、设置、退出；新档从中式主店门外开始，小镇↔餐厅↔厨房由门与物件交互进入。以最新要求覆盖 D030-TOWN 新档空地开局；已有建设接口保留。
- 正式经营复用 TDShopSession 的整数分钱、库存、菜单、自动订单、评价和日结；实体世界接入同一营业会话，不把旧世界实验账相加。旧场景/规则保留兼容测试。
- 用户 Q1：集市现货付款后立即入库；营业中禁止离店采购。远程供货原次日到货规则保持。
- 沿用筹备/日结存档边界；不保存进行中的 QTE。研习进度属于当前存档，营业奖励与当天一起保存。多槽互相隔离，旧档只读显式导入一个独立槽，不向新档自动复制。
- 调试控制台通过输入 debug 启用，普通玩家场景不出现刷客、伪造品质、修改SAN等按钮。设置不是调试。
- 美术：中式小镇、2D像素、木色/青瓦/暖灯；正式入口采用同一视觉语言。
- Grill实际来源：C:/Users/Administrator/.codex/skills/grilling/SKILL.md；无版本字段。依技能委派两个只读事实审查，问1题已答。GRILL_RESULT=RESOLVED。
- Godot技能：C:/Users/Administrator/.codex/skills/godot-gdscript-patterns/SKILL.md；无版本字段。新增位图使用内置image_gen，遵循imagegen技能。

## 验收标准

| AC | 输入与可观察结果 | 验证 | 状态 |
|---|---|---|---|
| AC-PHASE-4-G01 | 无存档启动：开始/继续/载入/设置/退出；新建独立槽，从中餐店外出生 | 真实入口集成/截图 | 自动PASS |
| AC-PHASE-4-G02 | 徒步到门口E：小镇、餐厅、厨房往返，原会话不重建、不重复信号 | 真实场景集成 | 自动PASS |
| AC-PHASE-4-G03 | 集市购买真实库存；门牌确认菜单/价格后营业；营业不能外出采购；厨房实际扣料/交付/结算 | 规则与联调 | 自动PASS |
| AC-PHASE-4-G04 | 同一完整包保存营业、研究、世界与布局；切换两槽不串钱/菜谱/布置，继续加载最近有效槽 | 存档往返/跨日 | 自动PASS |
| AC-PHASE-4-G05 | 损坏/未来版本拒绝；真实部分写入/备份阶段中断；显式恢复；旧档源不变 | 隔离目录故障测试 | 自动PASS |
| AC-PHASE-4-G06 | 正式界面无刷客/伪评分/SAN按钮；控制台debug开启后才允许调试命令，文本输入不触发走动/QTE | 输入集成 | 自动PASS，含最终Esc/装修输入复验 |
| AC-PHASE-4-G07 | 日结→次日、三日存读档保持经营账和研习；营业退出明确回退到最近边界 | 集成/人工 | 自动PASS；人工PENDING |
| AC-PHASE-4-G08 | 中式像素场景、主菜单、互动提示可读；设置窗口/音量实际生效并独立保存 | GPU截图/设置测试 | 图形/自动PASS；人工设备、美术验收PENDING |

## 协作与边界

基线 main@a164b1c；integration/phase-4-wave-game-shell。单Agent按角色顺序实施，事实代理只读。
economy/town/cook工作区在artifacts/game-shell-work/对应角色目录；cook仅更新厨房兼容测试中已被新要求取代的菜单标签。主入口、输入、存档公共装配和文档由集成者持锁。
保留两个未跟踪原始资料，不操作玩家真实存档，不自动提交/推送。

## 实际实现

- 正式标题：开始、继续、载入、设置、退出。新建6个独立槽之一，命名后出生已建中式食堂门外；继续选择最近成功保存的有效槽。原型入口通过反引号控制台输入debug后访问。
- 同一存档依赖贯穿小镇、餐厅、厨房。门和物件发出意图，场景切换保留营业会话、锅、订单和信号。餐厅客人使用已有订单的真实状态，没有另一套自动收款。
- 市场按钮只在与摊贩互动后的采购清单中出现，现货直接进入厨房实际库存；营业中不准离店。供应处沿用次日到货规则，重复领取不重复加料。开门前在营业牌勾选菜品、调价；打烊后看账本与收支、休息进入次日。
- 研习复用原Atlas和真实厨房练习，B与菜谱架都可打开。资格、最佳成绩、解锁和灵感随当前槽保存，营业奖励留到边界；新档之间不互相继承。用户显式导入旧进度时才读取旧营业/研习文件，原文件保持不变。
- 保存包统一校验四个领域；先写临时文件、读回校验、备份、替换。部分写入、备份后中断、未知版本、错误槽位和错误嵌套数据都有隔离测试。恢复备份也先验证槽ID，坏档/未来版本不自动变新档。
- 设置支持主音量、窗口/全屏与当前槽研习输入偏移。正常界面无刷客、伪造分数、修改SAN按钮；控制台debug后可查看状态、改SAN或进入独立旧原型。
- 三张新生成PNG：中式街景标题、食堂/民居/摊位/树木图集、餐厅家具图集。保留原厨师与厨房资源；真实地图道路/阻挡和餐厅布置仍由已有模型控制。

## 验证与失败记录

- 锁定 Godot 4.7.2.stable.steam.ed1daf0bf、Compatibility，GUT 9.7.1；未升级。
- 专项真实场景：artifacts/check/game-shell-integration-second，6/6、119断言、96.301秒，导入/加载/测试退出0。经过实际窗口输入路由完成三天备菜、QTE、交付和边界存读档，另测真实研习解锁/换槽。
- 专项存档：artifacts/check/game-shell-profiles-final，12/12、115断言、42.114秒；后续补跨槽备份拒绝和测试节点回收，纳入最终全量。
- 失败证据保留：game-shell-full-first 的绘制API参数解析错误已修复；game-shell-full-second 在600秒超时，明确FAIL；pre-export-20261023-182952 为366/368、7653/7655断言，两个失败分别是旧菜单标签预期和旧研究入口Esc恢复，已修复。未删测、未改为skip。
- 图形：artifacts/game-visual-delivery.log，实际 NVIDIA GeForce RTX 3050 Laptop GPU / OpenGL Compatibility，12张截图、退出0。检查标题、小镇、餐厅、采购、菜单、来客、厨房、暂停、研习、存档、设置、控制台。此项不是人工设备或乐趣验收。
- 角色所有权：cook2/economy9/town16项通过，integrator→main分支拓扑检查通过；角色核心文件以工作树副本为准集成。原两份未跟踪资料保留，未提交/推送。
- 全量：artifacts/check/pre-export-20261023-184702，38脚本、发现/执行/通过368/368/368，7659断言，0失败/0跳过，625.244秒；版本/导入/加载/测试退出码均0。旧研究测试有1条Float/Int比较警告，并有2处临时孤立节点提示（队列释放时机）；没有进程退出时ObjectDB泄漏或脚本错误，未隐藏日志。
- 导出：artifacts/export/summary.json，Windows开发包导出、392项运行资源白名单审计、程序启动退出均0；包含最终弹窗输入修正。运行包不包含测试/原始设计资料。启动带独立--validation-root到artifacts/export/smoke-storage。
- 全量运行期间最后补充了两处UI输入隔离：账本覆盖装修界面时禁用底层点击，Esc可关闭有文本焦点的控制台。最终源另跑game专项：artifacts/check/game-shell-input-final，发现/执行/通过6/6/6、124断言、124.168秒，0失败/0跳过，版本/导入/加载/测试退出均0。不把上一轮全量当作这两条新增断言的证据。最后代码修改18:51，导出包18:57已包含该版本；专项完成后仅更新文档。

## 关键文件

- src/app/main.gd / game_shell.gd：正常标题、当前槽装配、物件意图、暂停/覆盖层/控制台。
- src/business/game_profile.gd / profile_store.gd：同槽权威数据、候选研习事务、多槽与异常恢复。
- src/town/world_snapshot.gd、town_world.gd、town_art.gd；src/restaurant/restaurant_world.gd、restaurant_layout.gd、restaurant_iso.gd：持久世界、交互与像素呈现。
- tests/integration/test_game_shell.gd、tests/unit/test_shop_profiles.gd、tools/check.ps1、tools/export.ps1：实际入口、跨日/隔离/失败测试及统一导出检查。

## 未实现或未验证的边界

- 无新做菜替身：正常营业与研习都调用原厨房/QTE和原评分。测试时间线只是输入驱动器，不直接注入固定高分或伪造成品。
- 保存仅筹备/日结，不恢复QTE、排队客人或行走位置；载入在食堂门外出现。营业退出会提示当天未保存进度一同回退。
- 新入口未接入员工自动服务、分店和完整剧情；既有试验实现留在独立debug入口。其他菜系仍需剧情推荐，不自动开放。
- 六槽暂不提供覆盖/删除入口；旧档显式导入一槽。全球经营档/任意版本迁移不在本轮。
- 美术布局、真实键鼠与音频同步、连续经营疲劳均 PLAYTEST_PENDING；远程CI NOT_RUN。本地自动通过不能替代这些项。

## 五步试玩与复现

1. 打开build/TownDiner.exe（旁边保留PCK）；开始游戏直接进最近存档，无档则自动新建。另开一档使用载入存档→新建存档→空槽，可命名。WASD移动，在门前E进入餐厅。
2. 开店前到小镇菜摊E采购，回店营业牌E确认菜单和售价；首轮只勾选番茄炒蛋，可备番茄/蛋各4份，油/盐/糖/淀粉/酱油各1份。
3. 后厨门E进厨房，原操作取料/备菜/炒制/交付。回餐厅再走回厨房，确认锅与订单仍在；营业中试店门应提示不能外出。
4. 打烊后账本查看日结，B或菜谱架研习阳春面/蒸水蛋；到休息处进入次日。Esc可在边界保存；新槽检查菜谱不继承，再载回旧槽检查进度。
5. 反引号打开控制台，输入debug、help查看后门；Esc返回。试玩记录导航、菜单可读性、采购操作负担及连续营业感受。

检查：pwsh -File tools/check.ps1 -Suite game / -Suite profiles；全量pwsh -File tools/check.ps1；导出pwsh -File tools/export.ps1。默认每个检查进程1200秒，超时/零测试/必测跳过/错误仍失败。测试与导出启动检查使用artifacts隔离目录，不读取或覆盖真实玩家存档。

## 交付断点

本轮8项AC的自动部分通过，G07/G08人工部分待试玩；没有必测跳过。Windows程序与PCK已在build更新。共享工作锁释放，角色工作区保留供审查；没有提交、推送或发布。下一工作单元是用户试玩本轮单店流程并反馈，不自动启动其他Phase4开发。完整日志与失败历史保留在artifacts，原始设计资料未修改。

## D033入口反馈修正（2026-10-23，实施前AC）

- 来源：用户报告点击空档“从这里开始”没有反应；要求开始游戏直接进最近存档，与载入选档分开。
- AC-PHASE-4-G09：真实鼠标点击空槽创建按钮，创建所选槽并进入小镇；失败在当前界面显示原因；不覆盖已有/损坏档。
- AC-PHASE-4-G10：有有效档时点开始直接载入最近成功保存的槽，无选档步骤；无有效档时自动选择首个空槽创建默认食堂。载入存档仍可选已有槽，并保留明确的新档入口。无有效档且无空槽时给出恢复提示，不覆盖异常档。
- AC-PHASE-4-G11：检查真实鼠标按下/松开传播、重复点击、载入与返回；槽位与菜单都响应。导出包更新并验证启动。
- GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS；沿用实际grilling/godot-gdscript-patterns技能（路径同上，无版本字段）。没有新玩法问题，不重复确认。

### 根因与已完成修复
- 旧Windows导出运行时读取res://doc/source/ingredients.json；原始资料按发布规范未出包，导致Profile初始化失败、shop为空。创建页只显示不明显的资源路径；旧档导入再访问空shop会报错。源工程/带工程路径的编辑器运行会从磁盘找到该文件，因此此前场景测试与只进标题的导出smoke漏检。
- 实际旧运行程序鼠标复现：artifacts/title-native-before.log，空槽创建profile=false、NOTICE为缺失原资料，TITLE_PROBE success=false，退出1。这是明确失败，不沿用旧ENGINEERING_READY结论掩盖。
- TDIngredientBook改用显式派生的content/ingredient_index.json，包含全部历史ID/名称/sub；工具记录原文件SHA256并在检查入口校验一致。原风味/设计说明未转换为新机制，原资料继续排除出包。
- 开始/继续直入最近成功保存的有效槽，无档开始自动创建首个空槽。载入存档可选档或进入新建页；损坏/待恢复槽不会覆盖。标题/弹窗显示创建载入进度、清楚错误，忙时重复输入拒绝；创建/载入/旧档导入均检查初始化错误。
- 新增鼠标专项6/6、608断言、41.958秒，artifacts/check/title-entry-fix；版本/导入/加载/测试退出均0，0失败/0跳过。覆盖空槽、新档、最新槽、指定槽、重复点击、坏档保护与真实写入中断后下一空槽重试。
- tools/export.ps1新增实际Windows程序＋导出资源的隔离输入验证包；驱动脚本只在一次性包内，不进入交付包。

### 最终修正验收
- G09/G10/G11：自动PASS。最终全量artifacts/check/pre-export-20261023-193931，40脚本、发现/执行/通过374/374/374、8272断言、691.992秒，0失败/0跳过；版本/导入/加载/测试退出均0。既有数值类型warning保留，不隐瞒或算作跳过。
- Windows导出/393运行资源白名单/隔离标题启动退出0；运行索引含原资料14分类、250食材身份，原始资料仍未出包。实际导出程序＋同批导出资源通过真实鼠标输入的23项断言，artifacts/export/title-input.log，退出0；明确检查空槽进入、第二槽独立、旧槽不改、采购保存、开始进最近槽而不新建、载入指定旧槽。
- GPU：artifacts/title-native-after-gpu.log，Godot 4.7.2 stable official / Compatibility / NVIDIA RTX3050，23项通过、退出0；artifacts/title-native-gpu/run-2279824内四张截图，核对标题、空槽、新档店门外、已有存档。此为自动输入与画面检查，不能代替真人设备/乐趣验收。
- 新交付build/TownDiner.exe＋TownDiner.pck，2026-10-23 19:51生成。开始游戏直接进入最近存档，无档自动新建；需要另开档用载入存档→新建存档→从这里开始。保存边界及营业/QTE规则不变。
- 验证命令：pwsh -File tools/check.ps1 -Suite title；pwsh -File tools/export.ps1（内含全量检查与导出输入回归）。所有写入在artifacts隔离目录；原始资料与玩家档未动。economy13项所有权与integrator→main拓扑通过，角色核心哈希一致。无提交/推送；共享锁释放，人工PENDING、远程CI NOT_RUN，停在本次反馈修正交付点。

## 餐厅移动反馈修正（2026-10-23，实施前）
- 用户报告：人物在没有可见障碍的位置卡住、画面与碰撞不符。GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS；属于当前入口的移动缺陷，无新玩法产品决策。已读grilling、godot-gdscript-patterns实际SKILL.md，路径同本报告前文，无版本字段。
- AC-PHASE-4-G12：真实入口同时保留小镇/餐厅/厨房；餐厅所有相邻可走格中心之间的物理移动无外场景阻挡，重复切场景不产生新阻挡；厨房原过道/墙体仍有效。真实CharacterBody2D碰撞与输入路由测试。
- AC-PHASE-4-G13：没有家具的功能分区可走；真实餐桌/墙体阻挡。拆除/移动家具后旧位置恢复通行，新位置阻挡。顾客寻路与玩家物理读取同一布局事实；旧合法布局读写不变。
- AC-PHASE-4-G14：人物脚底与物理原点投影对齐；家具可见占地提示对应布局。图形检查门口、餐桌四周、空分区与厨房往返；人工手感仍待试玩。

### 复现与阶段验证
- 修复前artifacts/check/restaurant-motion-before：18项中15通过、3失败，175/187断言、退出1；餐厅176条可走格之间的移动命中隐藏KitchenWorld/CountersAndWalls或Town的StaticBody；厨房走廊也被其他场景挡住。真实输入在餐厅过道位移为0。保留该失败证据。
- 修复后artifacts/check/restaurant-motion-after：19/19、201断言、18.688秒；版本/导入/加载/测试退出0、无失败/跳过。232条餐厅相邻可走路径零阻挡；真正桌子/墙仍阻挡，拆除/移动后物理更新；三个来回及键盘移动/暂停通过。旧“空D区也挡人”测试改用真实墙体#，另增空ordering地砖通行测试，不删除物理保护断言。
- 源工程GPU检查artifacts/restaurant-motion-gpu.log：Compatibility/NVIDIA、29项入口与移动检查通过；9张截图，目录artifacts/restaurant-motion-gpu/run-2949047。该次后补家具与人物地面深度排序；最终图形验证以导出后记录为准，不能将此前截图当最后代码证明。
- 整文件集成复制被自动审批以“可能覆盖未提交改动”拒绝；随后逐文件比较差异，仅使用带上下文的小补丁合入，所有town核心文件及新测试哈希一致。没有绕过审批覆盖文件。town19项所有权检查通过。
- 最终全量artifacts/check/pre-export-20261023-204745：41脚本、发现/执行/通过378/378/378、8318断言、492.291秒；0失败/0跳过，版本/导入/加载/测试退出均0。既有数值类型warning保留。Windows导出/393资源白名单/独立启动退出0，build/TownDiner.exe与PCK于20:56更新，包含最终地面深度排序。
- 导出输入初检失败：引导打包工具把await physics_frames(...)前缀误替换成SceneTree调用；native进程虽退出0，SCRIPT ERROR仍被检查入口判失败。原日志artifacts/export/title-input.log和summary-movement-first.json保留；工具改为换行归一化后精确替换单数信号，检查最低数量提升到29。不改生产代码或包，仅重建一次性验证PCK并重跑受影响步骤，没有声称整条export命令重跑。
- 最终实际Windows运行程序重检：movement-probe-pack-recheck.log、movement-native-headless.log、movement-native-gpu.log，均退出0、无脚本错误；两种运行模式各29/29，232条路径阻挡0。GPU使用Godot 4.7.2 stable official / Compatibility / NVIDIA RTX3050，9张截图在artifacts/movement-native-gpu/run-1763109，核对空功能区、桌边人物遮挡、通道与厨房。artifacts/export/summary.json记录组合验证及重跑来源。
- G12/G13及G14自动部分PASS；人工手感PENDING、远程CI NOT_RUN。town19项所有权和integrator75项拓扑检查通过，核心文件与角色工作区哈希一致，共享锁释放。新旧数据文件、玩家档和原始美术未改，未提交推送，停止本次移动修复。
- 复测：pwsh -File tools/check.ps1 -Suite movement；最新导出程序进店后沿收银台空地和餐桌四周行走，往返厨房三次，确认空地可走、家具仍挡人。无需新建或迁移存档；真人试玩结果待用户反馈。
