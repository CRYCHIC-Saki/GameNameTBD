# D060 多家分店与星级店长（2026-11-07）

状态：DELIVERED_LOCAL_PLAYTEST_PENDING。工程与本地包已完成，只交付本轮增量，不代表整个 Phase 4 完成。原资料及 D057–D059 未提交成果保持；未提交或推送。

## 需求审查与来源

实际读取并执行 `C:/Users/Administrator/.codex/skills/grilling/SKILL.md`（无版本字段），使用其只读事实调查及依赖问题流程；同机 `godot-gdscript-patterns/SKILL.md` 用于组合与信号边界。两题用户均已确认，不再要求开始许可。

- USER_CONFIRMED：主镇也可开多家；外镇沿用开放进度；矩形选址须保护道路、住宅、他人产权和既有设施。面积与位置影响容量、初期费用、租金，同镇共享有限客流。
- USER_CONFIRMED：选择菜系、位置/矩形，再选必需店长；店长 1/2/3 星、四维面板、高星更贵且 2/3 星有特长。店长带基础厨服班组自动采购营业，玩家管理菜单、价格和每日预算；费用分项、可亏损。
- 来源：用户本轮及两题回答；大纲 §8.5–8.7；1013 会议菜单和三岗位；D036 五镇、D059 保存时点。Onboarding §91–180 天数字仅案例，不采用为统一平衡。
- 覆盖 D023/D041 正式入口的一家异镇、自动选址及逐份手动备料。旧快照须显式兼容，不重扣开办费；旧实验规则保留兼容测试，正式界面不能并列暴露两套分店。
- 现状缺口：旧 can_place 允许住宅覆盖；旧镇列表13镇；旧客流0–8独立产生，不满足共享客流；旧维护欠额丢失。新实现不能直接沿用这些行为。
- PROPOSED / AI-069：招徕、运营、品控、节约四维与初始成本/工资/技能倍率外置；远镇使用管理选址图，不声称新增跨镇旅行。参数待试玩。

## 验收标准

| AC | 输入条件 / 可观察结果 | 验证 |
|---|---|---|
| AC-PHASE-4-D060-001 | 正式账本/营业牌进入，选菜系→地图拖矩形→选店长→报价确认；取消不扣款 | 真实场景与GPU |
| AC-PHASE-4-D060-002 | 任意拖向，同镇多店；道路/住宅/厂地/水域/已占地/不临路拒绝；无款无店长无部分提交 | 规则与集成 |
| AC-PHASE-4-D060-003 | 三星级四维与明确特长真实影响能力；只可选已解锁匹配菜系菜单，不能因开店解锁菜谱 | 单元/集成 |
| AC-PHASE-4-D060-004 | 同镇所有店共用用餐机会及家庭资金；有限原料/预算自动采购，缺料不开虚假订单 | 经济集成 |
| AC-PHASE-4-D060-005 | 初期费一次；租金、水电、班组/店长工资、耗料及税分项；欠款保留；重复日结/重载不重复钱物 | 多日与幂等 |
| AC-PHASE-4-D060-006 | 多店独立菜单/库存，统一Shop现金和整槽保存；旧分店不丢已付款状态；普通退出不存 | 隔离存档 |
| AC-PHASE-4-D060-007 | 地图占地可见、账本可核对、操作可复现；导入/加载/专项通过，未做人工明确PENDING | 检查/导出 |

## 验证记录

起点 `branch-baseline-20261107`：导入/加载/存档 profiles 15/15、0失败/跳过、exit0。仅起点基线，不代表新功能通过；最终证据如下。

- `branch-first-load` FAIL：14/15，新增地图重装使旧地图首物件顺序变化；按恢复后的稳定ID保留并移除不必要重装。
- `branch-first` FAIL：新测试有静态类型错误、旧版本断言7需更新为8；未计零测试/被忽略测试为通过。
- `branch-core-second` FAIL：测试误用仅OPEN有效的close_early模拟未开门日末，存储Callable引用临时对象失效；改用真实close_for_night、保留测试仓库实例。没有降低生产门槛。
- `branch-core-third` PASS：14/14、177断言、31.749秒，导入/加载/测试exit0，0跳过。包含实际主场景、viewport矩形输入、菜单/预算、隔离存档。
- Compatibility图形探针首轮31项中1项失败：磁盘JSON把整数解析为浮点，Dictionary严格类型比较不等；资金和数据无丢失。保留gpu-first.log与gpu-first-summary.json，重新以项目既有same_value逐字段数值等价比较（非调用生产结算公式）。复验31/31、7图、exit0；expected-stores.json/loaded-stores.json保留原始双方，类型记录2→3。人工PENDING。

### 最终结果

- `artifacts/check/branch-regression`：11文件、79/79用例、5861断言、433.270秒，0失败/跳过，导入/加载/测试exit0。覆盖旧分店兼容、整槽保存、等级、住所与地图迁移、实际场景和经济联调。
- 最后补严损坏分店编号、非法面积及小屋重叠校验，拒绝载入且不污染当前槽。`artifacts/check/pre-export-20261107-214226`：2文件、17/17用例、207断言、48.567秒，0失败/跳过，导入/加载/测试exit0。与79项有重复，不相加声称96个独立用例；最后校验改动后未重跑全部79项。
- `artifacts/branch-expansion/gpu/summary.json`：真实Compatibility渲染32项通过、7张截图、exit0、stderr空。含实际鼠标框选、店长选择/确认、两家分店、附近E交互、三日运行、磁盘保存重读与账目核对。已检查地图、店长卡片与日账截图；这是自动图形检查，不等于人工经营体验验收。
- `artifacts/export/summary.json`：导出PASS、574运行资源、实际EXE启动3轮×4帧、实际EXE headless交互94项通过，所有exit0。本轮分店专用图形检查在编辑器执行；未在导出EXE另跑分店GPU探针。
- `build/TownDiner.exe`与`TownDiner.pck`于2026-11-07 21:43:44–45重新生成，必须同目录使用；正式版本仍为DEVELOPMENT_DEMO。
- AC-PHASE-4-D060-001至007工程检查全部PASS。人工长期盈利/费用/竞争强度、菜单理解与连续经营体验PENDING；完整仓库全量套件与远程CI NOT_RUN。未操作真实玩家存档。
- 最终协作检查PASS：integration分支、integrator、115条工作区路径；`git diff --check`未发现空白错误，仅既有CRLF规范化提醒。写入锁释放，用户原始资料和其他未提交成果保留，不提交推送。

复现入口（仓库根目录PowerShell）：`pwsh -NoProfile -File tools/check.ps1 -Suite branch-core`；相关回归用`-Suite branches`。本地构建：`pwsh -NoProfile -File tools/export.ps1 -CheckSuite branch-core`。引擎锁定4.7.2.stable.steam.ed1daf0bf、Compatibility、GUT9.7.1，未升级。

关键实现：`content/branches.json`、`src/business/branch_network.gd`、`src/business/branch_panel.gd`；Profile/Shop/WorldEconomy/Shell只做对应装配和唯一现金账接入。测试入口：`tests/unit/test_player_branches.gd`、`tests/integration/test_branch_panel.gd`、`tools/branch_probe.gd`。

## 能力边界

正式实现：多家独立分店状态、同镇抢客、按实际市场价格和有限库存原子采购、真实家庭付款、原料批次保质期和成本、店长四维/特长、容量、分项费用/欠费、同日组合等级、幂等日账、明确保存。
分店采用后台结算，不生成独立实时厨房/QTE场景；基础厨服班组薪资计入服务部门，不生成新的具名NPC家庭。远镇管理地图沿用已有经济布局，不等于客运已实现。没有用替身替代金融/顾客/地图集成。
旧单店原始菜单/员工/历史账完整归档；可映射库存转为新批次，未知原料留在legacy.unmapped_stock不丢弃，但不冒充可直接用于新菜谱。不可安全沿用的位置寻找合法位置；初期费不重收，次日起新规则营业。

## 五步试玩
1. 正常筹备或打烊后，在营业牌/账本进入分店，先观察菜系/地块/费用。
2. 拖一个临路3×4矩形，比较三个店长的薪酬、容量与特长，选定确认；尝试道路和已有建筑应拒绝。
3. 为两家分店设置不同菜单/价格与预算，主动保存后睡觉到次日。
4. 经营一天并日结，查看真实接待人数、采购/耗料及各项费用，比较利润和欠费；读档核对不重复结算。
5. 下调高价或调整预算再经营，记录客流变化和是否好理解。工资/费用/竞争强度仍需人工平衡。
## D062 世界地图选址（2026-11-08，DELIVERED_LOCAL_PLAYTEST_PENDING）

来源：用户“把开分店选择分店位置和范围那里改成世界地图，支持世界各地开分店”。五镇范围沿用 D036/D061；本次覆盖 D060 将开店绑定货运路线的限制，不改变菜系/食谱解锁。
实际读取 grilling：`C:/Users/Administrator/.codex/skills/grilling/SKILL.md`（未声明版本），并按其要求完成只读事实核查；Godot 使用 `C:/Users/Administrator/.codex/skills/godot-gdscript-patterns/SKILL.md`。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：用户已明确世界选址、五镇、多店、矩形与店长；费用和经营规则复用已确认方案。

| 验收 | 输入及可观察结果 | 验证 |
|---|---|---|
| AC-PHASE-4-D062-001 | 正式分店入口显示同一五镇世界图；点击镇、缩放/平移后框选得到准确当地坐标，报价后聘经理开办 | 真实场景输入＋GPU |
| AC-PHASE-4-D062-002 | 新档只有本地货运路线，仍可在五镇各开店；商路、菜系与主店库存不被解锁/挪用；当地实际经营可结算保存 | 规则＋跨日存读集成 |
| AC-PHASE-4-D062-003 | 占地/水域/道路、无钱、缺店长、非边界拒绝；取消/失焦/跨地图拖动不误选；换镇清空旧选区 | 单元＋场景 |
| AC-PHASE-4-D062-004 | 普通 M 地图保持只读；新分店地图一致；退出不自动保存、显式保存可重读 | 场景回归＋导出 |

### D062 实现与验证结果

- 已实现：正式分店窗口复用 M 世界地图；五镇图上点选/快捷定位，滚轮1–12倍，中键平移，左键拖矩形；真实地籍网格与报价、店长选择、创建及原菜单预算相连。界面暂停恢复、换镇清空旧选择、失焦/越界/滚轮中断不误提交。地图只读副本，原规则再次校验土地与现金。
- 五镇都可开店，货运仍独立锁定；当地真实市场采购和家庭付款、费用税款、存读档全部复用原模块。没有新增替身经营、菜系解锁或存档版本。本轮未改价格与经理参数。
- 起点 `artifacts/check/branch-world-first`：17/17、exit0；增补五镇/操作中断测试后 `branch-world-second`：20/20、325断言、64.603秒；界面排版后 `pre-export-20261108-192944` 再验20/20、325断言、39.788秒；最终海外说明文字修正及逐镇断言后 `pre-export-20261108-193529` 再验20/20、330断言、51.435秒。各次导入、加载、测试exit0，零跳过。重复执行不能合计为独立用例。
- 普通地图/跨镇/托管回归 `artifacts/check/branch-world-travel`：11/11、155断言、84.158秒、0失败/跳过、全部阶段exit0。与分店20项合计31个独立用例、485断言。
- 图形首轮49项通过但人工看图发现餐馆类型栏挤压地图；已修正标签尺寸、隐藏空白通知、合并底部按钮，报价/下一步在1280×800可见。`artifacts/branch-world/gpu-layout.log`及`gpu/summary.json`：Compatibility49项、11图、exit0。不是以自动断言替代布局复核。
- `artifacts/export/summary.json`：591运行资源、导出exit0、实际EXE启动3轮×4帧、headless菜单交互94项PASS。正式EXE/PCK于2026-11-08 19:36:43–44更新；哈希记录`artifacts/branch-world/delivery-hashes.json`。
- 首次EXE图形命令使用`--main-pack`，导出模板不支持该参数，exit1（日志`export-gpu.log`），没有判为通过。改用同一EXE副本及同名隔离探针PCK，不修改发布包。最终 `artifacts/branch-world/export-gpu-final.log` / `artifacts/export/branch-probe/screenshots/summary.json`：实际导出Compatibility53/53、11图、exit0。逐镇简介与选择一致，真实鼠标在五镇框选并开六店、三天结算、显式保存重读、重复占地拒绝及世界现金守恒均通过。
- AC-PHASE-4-D062-001至004工程检查PASS；人工选址手感、跨镇长期盈利平衡PENDING。全仓全量与远程CI NOT_RUN，不沿用旧结果冒充本轮已跑。无真实玩家档/原始资料变更，未提交推送；不推进额外阶段。

### D062 复现与试玩（至多五步）
1. 启动 `build/TownDiner.exe`（PCK须同目录），筹备/日结时从账本或营业牌打开“分店→筹建新分店”。
2. 选择已掌握的餐馆类型；在世界图点击日本/欧洲/东南亚/墨西哥或主镇，滚轮放大、中键移动。
3. 左键框选临路3×4范围；查看绿色选区与费用，试框道路/建筑应红色拒绝。可点击世界全览改选另一镇。
4. 下一步聘1–3星店长并确认；按需要调整菜单/价格/预算，主动保存，然后睡到次日。
5. 日结查看当地分店采购、销售、房租/水电/工资及利润，重新载入核对。开海外店不会开放主店进口商路。

检查：`pwsh -NoProfile -File tools/check.ps1 -Suite branch-core`；地图回归`-Suite travel-core`；本地导出`pwsh -NoProfile -File tools/export.ps1 -CheckSuite branch-core`。实际引擎4.7.2稳定版、GUT9.7.1与Compatibility均未升级。


## D067 付款施工与分店巡视（2026-11-09，DELIVERED_LOCAL_PLAYTEST_PENDING）
实际读取 grilling 与 godot-gdscript-patterns（C:/Users/Administrator/.codex/skills/ 对应目录/SKILL.md，未声明版本），只读代理核查原迁移及地图入口。用户确认本轮室内只巡视管理、员工继续经营，暂不亲自接管分店QTE。GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS（已答唯一阻塞问题）。
- AC-PHASE-4-D067-001：框选/取消/付款失败不生成分店、不占地、不扣钱；成功确认只扣一次并持有付款凭证。用正式面板和规则集成验证。
- AC-PHASE-4-D067-002：付款后显示施工地，1个游戏日后建成；施工中不可进入/营业/计执勤工资，保存读取不缩短工期。日期由原日循环推进，暂停和time set不推进日期。
- AC-PHASE-4-D067-003：建成无店长不能营业、开启托管不能绕过店长；沿用三岗位齐备要求。撤任店长立即停止接受分店交易，重复结算不重复收费。
- AC-PHASE-4-D067-004：五镇施工/建成状态同源，E进入对应分店餐厅→厨房→餐厅→原镇门外，真实移动/输入/碰撞/暂停，无主店钱物串用或第二套后台模拟。
- AC-PHASE-4-D067-005：旧正常开办凭证和合法旧版付款保留；无凭证旧记录保留为待核对选址，不画成房屋、不营业、不自动补扣钱。主动确认付款后才能施工；付费供货/历史账引用原ID保留。
- AC-PHASE-4-D067-006：整槽隔离往返、错误付款/工期/重复凭证拒绝；原主店经营与手动保存不变。实际图形/本地导出独立记录，人工巡视感受PENDING。
【AI填充细节 AI-077】工期先为1个日历跨日，次日08:00建成；施工日不收房租/水电/岗位日薪，完工日开始房租；未配齐岗位不发生开门水电。旧不明凭证记录不作可营业店铺，但保留引用以保护已付供货/旧工资账。巡视内景复用既有像素资产与移动表现，布局暂不支持装修，不新增客流、菜品或存档权威。

### D067 实现与实际验证
- 原因范围：原正式open_store已经先付费；复现旧branch_open标记无Shop凭证仍迁移“原分店”的路径，并补上付款交叉校验。未读取真实玩家槽，不能证明用户该档必定源于这一条路径。待核对旧记录保留完整原状态及ID、已付款供货可继续收货，但不预留地图、不营业、不新购料；主动付款再校验原地块，已被占用时拒绝且不扣钱。
- 真正实现：报价/支付/凭证/工期、5镇同源建筑状态、店长门槛、施工费用隔离、巡视室内/输入/碰撞/地图返回、存档迁移与校验。分店沿既有共享顾客池和后台员工经营；没有第二套经济，也没有测试替身替代正式场景。单位测试为控制边界可注入已有员工模板，最终GPU则通过真实招聘签约、派驻和定向供货。
- 暂未实现：玩家接管分店QTE、分店独立装修、逐位顾客室内用餐演出、各镇新室内美术；巡视房间复用既有餐厅/厨房与员工呈现。开办/租金/工资原参数保留，新工期与费用起算是AI-077，人工平衡待测。
- 新专项 `artifacts/check/pre-export-20261109-194824`：11/11、175断言、37.649秒，导入/加载/测试全部exit0，零跳过。含正式场景E键、取消、暂停、反复进出、5镇日期投影、未知旧记录与合法新店同地不冲突、真实JSON往返。
- 旧分店/列表/主店管理 `construction-old-core`：30/30、522断言、49.554秒；员工/供应商/HUD/经营/跨镇/保存/等级/控制台 `construction-regression-final`：93/93、3605断言、204.085秒。分批共134个独立用例、4302断言，不代表全仓全量单次通过。最后只改待核对行标题和导出清单后，重新执行上述专项11项；未因此再重跑全部旧用例。
- 图形 `artifacts/branch-construction/gpu-final.engine.log` / `gpu/summary.json`：Compatibility50项、9图、exit0、stderr空。真实按键及移动、施工拒绝进入、主镇/东京进店进厨房、本店库存和返回原镇检查通过；已人工查看自动截图，未进行玩家连续试玩。原第一轮41项画面用于发现厨房人物显示偏小和账本位置，修正后最终复验。
- 导出首轮FAIL：正式清单把两个脚本路径误合成一个字符串，包资源检查拦下缺失branch_interior；日志完整保留在`artifacts/branch-construction/export-first-failure/`。修正为两个独立资源后重新导入、加载、11项测试、导出/清单/实际EXE启动3×4/headless94输入检查全部PASS，609资源；2026-11-09 19:49本地EXE/PCK更新。分店专用GPU在源工程执行，导出EXE分店专用GPU NOT_RUN。
- 其他失败保留：红测6项1过5败；初轮类型/JSON数字版本比较导致旧场景存档失败；8/9轮地图覆盖层冻结检查改查真实process_mode；旧供应回归56/59发现施工期预备货被过度限制，改为已付款即可提前供货，最终93/93通过。不是把零测试/解析失败/超时判为通过。
- AC-PHASE-4-D067-001至006工程PASS，人工PENDING，全仓全量/远程CI NOT_RUN。原始资料和真实存档未操作，未提交推送。协作检查integrator/integration通过，git diff --check退出0，仅既有CRLF规范化提示。root本轮写入锁释放。

### D067 复现与试玩
1. 启动`build/TownDiner.exe`，筹备时按G→增设店铺→地图选地；直接返回应无新店、无扣款。
2. 重新选地确认付款，地图出现施工标识，E不能进入；主动保存或睡觉，跨日后显示建成。
3. 暂不任命店长，查看“等待任命店长”，托管不能绕过；从H签约入仓库，在G本店店员页派驻店长、厨师、服务员并准备原料。
4. 到建成店附近E进入餐厅，再到厨房门E；走动、查看本店库存/菜单/员工，出门回到原镇原处。外镇同样可巡视；02:00仍按原规则收尾回家。
5. 比较施工日/完工日账本，核对前者无施工期租水电工资、后者有租金，缺岗无开门水电；主动保存读档核对。

命令：`pwsh -NoProfile -File tools/check.ps1 -Suite construction -TimeoutSeconds 300`；旧相关`-Suite construction-regression -TimeoutSeconds 480`及`-Suite branch-core`。导出：`pwsh -NoProfile -File tools/export.ps1 -CheckSuite construction -CheckTimeoutSeconds 300`。
关键文件：`src/business/branch_network.gd`、`branch_panel.gd`、`branch_interior.gd`、`game_profile.gd`、`employee_roster.gd`、`supplier_network.gd`、`src/app/game_shell.gd`、`src/town/travel_world.gd`与`content/branches.json`。
