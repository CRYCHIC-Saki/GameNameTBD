# Phase 1：完整做菜系统增量

## D016 玩家反馈修复（2026-10-10，当前验收）

| AC | 来源、输入与可观察结果 | 验证 |
|---|---|---|
| AC-PHASE-1-037 | 用户打谱要求：菜谱指定落刀/转向，全命中番茄谱得到块；错误/离拍转向不改状态，换谱改变目标而非改代码 | 手算窗口、方向/刀数、配置坏例和真实菜板输入 |
| AC-PHASE-1-038 | 用户反馈不足：命中/早晚/错键/漏拍显示可区分文字、音符色和短音；最后一拍结束后仍可见，重开无旧反馈 | 控制器事件、真实场景、GPU画面；实体听觉另列 |
| AC-PHASE-1-039 | 用户鼠标冲突：M6不与本锅M4重叠，双锅点柜时无手动控温要求、无暗扣/自动满分；游戏时间继续 | 配置占用校验、两真实会话输入/时钟 |
| AC-PHASE-1-040 | 用户时长反馈：每步预告可见，M7晚起手仍有完整蓄力与松手窗口；漏按有界结束，暂停/长帧一致 | 手算晚起手、超时/松手/暂停边界、完整自动流程 |
| AC-PHASE-1-041 | 修复后导入、加载、全部测试、干净副本、图形与Windows包验证；不把设备未验写通过 | 同一check入口、导出与人工PENDING |

状态：AC037–041工程PASS；实体输入/音画同步NOT_RUN，主观手感PENDING。实际使用grilling与godot-gdscript-patterns，准确来源见D016/D015；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS，用户最新四项修正已足够实施，无重复问卷。

### 本轮证据与复现

- `pwsh -NoProfile -File tools/check.ps1`：最终由export调用，`artifacts/check/pre-export-20261010-112301/summary.json`；219发现/执行/通过，23套件、1913断言，0失败/跳过，版本/资源导入/生产加载/测试均exit0。
- 无缓存干净副本：`artifacts/d016-clean-20261010-112650/干净 副本/`，同一入口`-ReportName final`得到219/219、exit0；证明中文空格路径和首次导入可用。
- 新增`test_recipe_performance.gd`的11项规则用例验证谱面与方向、±50/100ms边界/错键/重复输入、配置坏例、晚起手完整持有、暂停/超时/长帧/取消及控温托管；`test_guided_kitchen.gd`新增3项真实场景用例覆盖菜板输入与跨结束反馈、错峰双锅M6鼠标独占、真实M7延迟起手仍到目标。没有用测试替身替代这3项生产场景。
- 真实GPU运行：锁定Godot `--path F:/MyGameTBD --script res://tools/guided_visual_check.gd`，22张画面、delivered=true、exit0；`artifacts/d016-visual.json`。已自审Perfect/Miss文字和音符、M6无控温要求、M7实际持有游标。输入为Viewport真实事件注入，未宣称实体设备通过。
- `pwsh -NoProfile -File tools/export.ps1`：最终check后Windows导出/94项运行资源清单/独立包启动全部exit0；`artifacts/export/summary.json`。包为`build/TownDiner.exe`与`TownDiner.pck`，仍为开发演示，远程CI对本轮修改NOT_RUN。
- 六份原资料SHA256一致：`artifacts/d016-source-verification.json`。原资料只读、未改依赖版本、全局设置、真实存档或远程仓库。

### 当前配置与边界

番茄备菜第5/7/9拍为Space落刀、D转向、Space落刀，全中为块；转向失败不会偷偷成功。黄瓜条样例用另一张两个Space的配方谱，验证切型需求由谱表达。炒菜流程不变但时间调整为：M2第5拍；下油11/13/15、下料21/23/25；翻炒31–39、45–53、59–67；M4在31–68；M6在75/77/79；勾芡85/87/89；M7在97–100。BPM120，时间和新增内容值均PROPOSED，不是已验证平衡。前置预告、起手等待和实际蓄力各自计时，不再从固定短总时长中扣掉玩家起手等待。

界面反馈来自真实控制器的序号事件，不由UI伪造分数。自动漏拍也反馈；读取/松键不重复发布。双锅M6期间暂停另一锅手动控温判分而继续实际游戏时间与当前位置热量累计，完全托管不会得到免费Perfect。模型/评分/两会话独立和旧兼容测试继续复用。

### 中间失败保留

`artifacts/check/d016-red/`：211项中旧205项通过、新6项失败，exit1，证明用例能捕获原问题。`d016-first`为211/211、`d016-coverage`为218/218。最终自审新增坏例后，`pre-export-20261010-112052`出现219项中3项旧自建配方失败：新默认配方引用预检与旧单配方验证上下文冲突。现将候选放入完整目录上下文校验，保留引用约束和原测试，最终原工程及新副本各219/219。检查门槛逻辑未放宽；历史故意失败/必测跳过/解析错误/零测试证明仍见D015，本轮没有重复运行整套四类故障注入。

### 本轮交付与停止点

五步试玩：番茄送砧板→按Space/D/Space谱切块→搬锅并加鸡蛋，E自动炒制→调味只按谱点柜，出锅等待提示再长按并松开→端盘交付看评价。完整操作见README/PLAYTEST。引擎生成并实际调用提示音已验证；耳机/扬声器和物理按键的同步、玩家能否读懂反馈仍待试玩。更新后的节奏、托管规则和原型动作需要真实体验，停在Phase1，不提前执行Phase2。

## D015 玩家流程纠正（历史验收，节拍/转向/调味控温已由D016修订）

| AC | 来源与可观察结果 | 验证 |
|---|---|---|
| AC-PHASE-1-029 | 最新用户：食材、砧板、蒸笼、出餐口均有台面承载；碰撞与近距离E可达 | 实际渲染＋场景碰撞 |
| AC-PHASE-1-030 | §3及用户：番茄切完搬锅、鸡蛋入锅后E自动按完整炒菜链推进，无工序菜单 | 真实场景端到端，包含所有工序顺序 |
| AC-PHASE-1-031 | §4：一菜一表，逐拍hand/mouse、Tap/Hold/Rest，可留白、并行、重排和提前预告；输入时间实际使用表中拍号 | 配置坏例/手算节拍/分片一致 |
| AC-PHASE-1-032 | §3：七模块的环/火力表/方向串/引力/常驻炖煮/材料柜/长按条正确，错料Miss、出锅中心/边缘分档 | 控制器单元＋真实GUI输入 |
| AC-PHASE-1-033 | §5：两锅自动显示并发，固定键组＋共享空格，鼠标同时作用两控温游标，冲键明确 | 双会话与同帧输入测试 |
| AC-PHASE-1-034 | §6：按模块聚合q和权重，不因M3分成多段改变模块总权重；菜品与顾客评分仍独立 | 显式期望值单元 |
| AC-PHASE-1-035 | §7及用户：顶部菜名/要求、中央动作与QTE、底部共用节拍、右上属性、边缘炖煮条；无文档外操作按钮 | 真实GPU截图＋UI节点检查 |
| AC-PHASE-1-036 | 本轮最终源导入、加载、规则/场景、干净副本及导出通过，人工另列 | check/gate/export，人工PENDING |

状态：AC029–036工程PASS；实体设备与人工玩法PENDING。D014的190项工程通过不代表用户已验收界面；用户已否定旧交互，本轮以D015为准。最终205/205通过，不使用早期通过记录代替最新源代码检查。

### 实际实现、来源与AC映射

| AC | 本轮证据 | 结果 |
|---|---|---|
| 029 | kitchen_world的独立台面/交互坐标与ServingCounter碰撞；实际world截图；原真实移动/碰撞回归 | 工程PASS；路径体验待试玩 |
| 030 | test_guided_kitchen真实主入口、E取放、切菜后搬运、锅中全链顺序、唯一交付与无工序按钮；全无输入仍真实低分完成 | PASS |
| 031 | test_document_operations手算逐拍时间、Rest/并行、首拍点火预备拍、坏轨/引用/持操作缺拍拒绝；现有长帧和暂停分片回归 | PASS |
| 032 | 原QTE窗口/错序/长帧/取消边界；本轮M7中心/区内/区外、M4的50%/80%分档、真实十格柜和蒸菜完整顺序 | 工程PASS；物理输入/听觉同步NOT_RUN |
| 033 | 双锅真实集成：独立会话、共同鼠标吸引、共用横坐标、目标带分开、两锅都结束；M3提前Space真实计错 | PASS |
| 034 | 显式夹具验证M3含下油/翻炒/勾芡仍只用0.25权重；独立只读评分历史回归；真实两客人差异反馈 | PASS；数值仍PROPOSED |
| 035 | 18张真实GPU画面与节点检查；M5从世界到菜板均常驻；菜单只有进入/退出；视觉自审修正提示换行和双锅坐标 | 工程PASS；美术/可读性主观验收PENDING |
| 036 | 下方原工程、最终新副本、故障门槛、导出/包启动分别有日志/退出码 | 工程PASS；远程CI未运行 |

已实现的玩家流程：番茄炒蛋、番茄蒸蛋（TEST_ONLY）、炖牛肉M5（TEST_ONLY）、两锅并发、返回与暂停、端盘唯一交付和再做。新视图使用真实Lane/会话/QTE/评分，没有演示专用假规则或固定高分。原探针/FixedRandom等只用于既有依赖边界测试；15个新增用例中的6个使用真实生产场景，不以替身替代引擎联调。

关键文件：`src/kitchen/full_kitchen.gd`（装配/自动流）、`guided_cooking_view.gd`（玩家画面）、`cooking_lane.gd`（真实控制器/会话）、`src/world/kitchen_world.gd`（台面与E）、`src/qte/beat_sheet.gd`和`cooking_qte.gd`（输入时间线）、`src/cooking/cooking_model.gd`（模块聚合/效果）、`content/cooking_system.json`（唯一活动配置）。共享接口与归属见CONTRACTS/COLLABORATION。

### 当前建议节拍表（不是已验证平衡）

| 流程 | 实际拍点，120BPM |
|---|---|
| 砧板M1 | 2/3/4/5/7/8，6为空拍 |
| 炒菜M2 | 第5拍点火，提前给扫动预告 |
| 下油/下料M3 | 9–11 / 14–16，每段末拍Space |
| 翻炒M3 | 19–23 / 27–31 / 35–39，段间留白 |
| 炒制M4 | 19–50，16秒；43–45鼠标去点柜子，温控仍继续 |
| 精确调味M6 | 43盐 / 44糖 / 45油 |
| 勾芡M3、出锅M7 | 53–55 / 61–62持2拍 |
| 蒸菜 | 之前实际M1备菜；3–5调味，9–16上笼持8拍，留白，25–26出锅 |
| 炖煮 | 5点火，9–40持续M5，45–46出锅 |

这些拍号是数据，不是硬编码“第几小节做什么”。编译目标时间会跟随有效拍点重排；相冲突配置加载即拒绝。M4/M5连续采样累计停留比例，M3/M6的序列档位与模块平均分别计算；源码矛盾与权重补值明确列在D015。

### 实际验证与复现

- `pwsh -NoProfile -File tools/check.ps1`：最终运行由export调用，`artifacts/check/pre-export-20261009-223812/summary.json`；205发现/执行/通过，22套件，1812断言，0失败/跳过；版本、导入、45项生产资源加载、测试均exit0。
- 最终干净副本 `artifacts/guided-clean-20261009-223811/干净 副本/`：同一入口 `-ReportName final`，205/205，导入/加载/测试exit0。含中文和空格路径，未复制.godot缓存。
- `pwsh -NoProfile -File tools/verify_gate.ps1`：`artifacts/gate-20261009-221502/gate-proof.json`，正常/恢复204项exit0；故意失败、必测pending、解析错误和零测试exit1。门槛之后修了双锅坐标、暂停提示层级和相邻指令串预告，检查脚本未变，最终源又在新副本完整通过。
- 锁定Godot运行 `--path F:/MyGameTBD --script res://tools/guided_visual_check.gd`：Compatibility/NVIDIA RTX3050实际渲染18张图，交付true、exit0；`artifacts/guided-visual.json`和同名前缀图片。注入的是真实Viewport事件，但不是实体设备。
- `pwsh -NoProfile -File tools/export.ps1`：最终全量检查后导出Windows EXE/PCK，94项运行资源清单，export/pack-manifest/smoke分别exit0；`artifacts/export/summary.json`。排除GUT/测试/源资料/工具/dev入口；开发演示包含明确测试样例。远程CI仅配置NOT_RUN。
- 六份源资料SHA256一致，`artifacts/guided-source-verification.json`。没有改写原资料、真实存档、全局Git或远程仓库。

### 中间失败与修复（保留事实）

`document-flow-first`曾超时：新界面仍触发旧隐藏界面全量刷新，且每帧复制整份配置，已改私有只读缓存并停止隐藏布局刷新。`document-flow-cached`为197/199：旧鼠标回归被document标记误挡、配方数量旧断言仍为3，分别修正兼容条件与当前5条内容断言。`document-final-review`加载失败来自新增配置预检误把下油当M6，修成与模型相同的oil配置后通过。后续图形自审再修了旧菜单、提示换行、常驻条、反馈截断、双锅坐标和暂停提示层级；最后的配置边界自审修了相邻合法指令串被预告重叠误拒绝，新增手算输入时刻验证。上述日志不删除，也不记成成功。

### 交付与停止点

五步试玩：拿番茄到砧板→按拍备好并搬锅，再搬鸡蛋→空手灶台E按自动提示烹饪→长按出锅后端到出餐台→看反馈再拿料。细节见README/PLAYTEST。

风险：节目节拍与材料数值仍建议值；完整命中6刀会成丁，和“大块”客人的教学取舍未验；蒸笼共用右锅；程序绘制动作和占位节奏不是最终资产。原SAN/自由工序/配方库等底层历史规则保留回归，但不作为当前可点击功能。仍需真人键鼠/音响同步、控温与双锅手感、差评引导和美术体验验收。停在Phase1，下一步是本阶段试玩反馈，不自动进入Phase2。

## D014 操作与搬运增量验收（历史检查点）

来源：用户最新要求、做菜操作.md M1–M7/§4–7；D014记录冲突与假设。本轮基线165/165，exit0：artifacts/check/operations-baseline。

| AC | 输入与可观察结果 | 验证方式与结果 |
|---|---|---|
| AC-PHASE-1-021 | 料箱→拿取→菜板落刀→取走→灶台投料，实例属性/历史不丢失，不隔空添加或复制 | PASS：test_pc_cooking转移原子性＋test_pc_kitchen真实世界E输入 |
| AC-PHASE-1-022 | M1空格逐拍，A/D转向；成功刀数/方向与品质独立；零命中不切碎 | PASS：test_pc_operations方向/精度，test_pc_cooking形态/释放，真实切菜场景 |
| AC-PHASE-1-023 | M2扫动点火；M3按拍WASD并以空格收尾；M7长按后松手 | PASS：五类控制器旧边界回归＋PC窗口/错序/超时/取消/蒸制场景 |
| AC-PHASE-1-024 | M4鼠标吸引与M3并行；M5更稳且离开持续，HUD可见；双菜共享鼠标不串会话 | PASS：固定时间线/长帧一致；真实Viewport鼠标和双键盘、后台炖煮场景 |
| AC-PHASE-1-025 | M6逐拍点击材料柜，错料和错序有实际味型差异；无输入不自动加料 | PASS：真实GUI点击、错误材料手算、非法结果原子拒绝；份量默认0.10回归 |
| AC-PHASE-1-026 | 可配置BeatSheet允许留白与键鼠并行；共享拍点/音轨、辅助开关；非法时表拒绝 | 工程PASS：配置/时表测试、无输入真实Miss、循环音轨资源、图形；实物音画同步NOT_RUN |
| AC-PHASE-1-027 | 满手/忙碌/重复转移/暂停/失焦/重开清理明确；成品搬到出餐台仅交付一次 | PASS：模型/生命周期及场景重复交付；校准控件覆盖菜板与双锅 |
| AC-PHASE-1-028 | 同入口导入/加载/全部回归、导出启动；真实渲染；物理设备/玩家体验单列 | 工程PASS：190/190，44资源加载，干净副本/故障门槛/导出；人工PENDING |

工程状态：ENGINEERING_READY；PLAYTEST=PENDING。未把旧165项结果当成本轮验收。实际使用grilling与godot-gdscript-patterns（路径见D014，无版本字段），先派只读事实审查后核对已答决策；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS，没有重复提问。

### 本轮实际实现与边界

- 实现：真实拿取/放下/菜板/两锅/端盘/出餐；保持实例身份与处理历史的原子搬运；M1–M7输入、同菜温控与手部并行、节拍表、共享节拍/循环占位音轨、鼠标弱/强引力、离开炖煮HUD、辅助和校准、方案v2兼容读写。复用既有六属性/反应/评分，没有平行菜品模型。
- 核心文件：src/kitchen/kitchen_handling.gd、full_kitchen.gd、cooking_lane.gd；src/cooking/cooking_model.gd；src/qte/cooking_qte.gd、beat_sheet.gd、temperature_view.gd、cooking_action_view.gd；content/cooking_system.json。公开契约/所有权见CONTRACTS、ARCHITECTURE、systems/cooking。
- 测试：保留165项既有验证，新增9项QTE、9项规则与7项PC场景，共190项。旧full_kitchen场景显式使用legacy配置验证兼容；新PC场景走生产配置、实际Godot节点、GUI鼠标和键盘路由，不以旧测试冒充新操作通过。FixedRandom只用于可注入规则边界；生产流程没有伪造分数或假完成。
- 限制：供料无限、单手/单菜板；蒸笼与右锅共用槽位。功能位、动作、UI和音轨为占位表现，不是正式美术/歌曲。旧任意批次、保温与SAN测试控件未搬进PC界面，底层保留回归。经营、库存、世界进程、完整SAN成长仍不做。所有新数值PROPOSED，两刀映射等ASSUMPTION见D014。

### 实际检查证据

- `pwsh -NoProfile -File tools/export.ps1` 调用同一检查链；最终 `artifacts/check/pre-export-20261009-193001`：导入/加载/测试exit0，44生产资源，20套件、190发现/190执行/190通过、1706断言、0失败/跳过。Windows导出/包清单/独立启动exit0，92运行资源；artifacts/export/summary.json。包为build/TownDiner.exe＋TownDiner.pck，排除文档、工具、GUT、测试与独立dev入口。
- `tools/verify_gate.ps1`：artifacts/gate-20261009-192500/gate-proof.json，clean/restored各190/190 exit0，故意失败/必测跳过/解析失败/零测试各exit1。随后仅修正份量控件步长及其浮点断言，最终完整源又在全新无缓存中文空格副本 `artifacts/pc-clean-20261009-193027/干净 副本/artifacts/check/clean-final` 导入并190/190通过。
- 图形：tools/pc_visual_check.gd从真实入口运行，8张pc-*.png，交付和材料柜GUI均true，Compatibility/OpenGL3、NVIDIA RTX3050 Laptop，exit0且无运行时报错/泄漏。截图检查修复了世界功能位被背景遮挡、动作拉伸和输入框裁切。实体键鼠与耳机/显示器同步NOT_RUN，人工可理解性/好玩程度PENDING。
- 校准回归真实注入晚125ms的键盘输入并正确判Perfect；这只验证时间接口，不能替代物理设备同步。原六份资料指纹全部不变：artifacts/pc-source-verification.json。远程CI配置完成、NOT_RUN；没有推送或发布。
- 中间真实失败日志保留：吸引力暂停残留、GUI测试覆盖层拦截点击、JSON数值版本比较、音轨清理、校准测试大小写及份量浮点精确比较等，已修复后重新检查，不把失败日志改成通过。

试玩不超过五步见README或PLAYTEST。下一步仅等待用户体验反馈并在Phase1继续修复；本轮停在Phase1检查点，不自动进入Phase2。

## D013完整系统检查点（历史，旧操作被D014修订）

当前结果：ENGINEERING_READY / PLAYTEST=PENDING。以下20项自动/工程部分PASS，无未实现的必做机制；物理键鼠/音频同步及玩家体验NOT_RUN/PENDING。全量165/165、1524断言、41资源加载、导入/测试exit0；干净副本165/165及四种故障门槛验证完成。证据`artifacts/check/pre-export-20261009-171533`、`artifacts/gate-20261009-171821/gate-proof.json`；Windows包86项运行资源，导出/独立启动PASS。完整图形5张、flow=true，另九动作图；远程CI未运行。

D013已确认完整做饭系统＋五类QTE＋像素厨房，覆盖旧原型收窄限制。按doc/agent_prompts/Phase_1.md A–J及18项AC执行，增加可走动厨房与烹饪动作两项。旧原型结果在本文下方保留历史，不以旧76项代替本次全量检查。

技能实际来源：`C:/Users/Administrator/.codex/skills/grilling/SKILL.md`、`C:/Users/Administrator/.codex/skills/godot-gdscript-patterns/SKILL.md`，均无版本字段；按总控使用grilling完成三项增量审查，答案D010–D012，范围D013，GRILL_RESULT=RESOLVED。像素资产使用`C:/Users/Administrator/.codex/skills/.system/imagegen/SKILL.md`与内建生成工具，实际PNG、提示词与来源见assets/kitchen/README.md。动画/判定图为原生Godot代码绘制，无第三方音乐/角色复制。

| AC | 来源、条件与可观察结果 | 实现 / 实际验证入口 |
|---|---|---|
| AC-PHASE-1-001 | A：非法ID/引用/范围/数量拒绝，启用清单唯一 | cooking_catalog.gd / test_full_catalog |
| AC-PHASE-1-002 | A：同模板多实例与双会话独立，无模板污染 | cooking_model.gd / test_full_cooking.instances、场景双槽 |
| AC-PHASE-1-003 | B：六属性、28味、主/复合并列、五档H、边界和纯读取 | cooking_model / test_full_cooking、test_full_storage_scoring |
| AC-PHASE-1-004 | C：自由顺序真实改变效果，非法请求原子拒绝 | model / heat_order、merge、invalid_* |
| AC-PHASE-1-005 | C：四热反应、勾芡/发酵/暴露正反例与边界，单次触发 | model / each_thermal_reaction、starch_fermentation、真实场景remaining_operations |
| AC-PHASE-1-006 | B/D：相同输入时间线分片不改变结果；非帧数计分 | cooking_qte、Lane边界切分 / test_full_qte及scene_fixed_seed；容差1e-9～1e-5 |
| AC-PHASE-1-007 | D：五类真实输入接入工序，开始/结束/取消/复位 | cooking_qte / 25项QTE单元、all_five_real_qtes场景 |
| AC-PHASE-1-008 | D：时间窗两端/重复/长帧/暂停/失焦/旧回调 | QTE单元、Lane/FullKitchen场景；物理设备NOT_RUN |
| AC-PHASE-1-009 | E：两QTE同时推进；同帧两侧键、单侧重开、随机独立 | full_kitchen / dual_input_routing场景与种子测试 |
| AC-PHASE-1-010 | C/F：返工保留历史；过火/缺料/取消/报废/交付限制 | model / rework、plate_early_late_timeout、场景free_plating |
| AC-PHASE-1-011 | F＋D012：真实拖盘、盘内不改属性、盘外松手报废、交付一次 | plating_view / 真实Viewport鼠标事件与模型/信号场景测试 |
| AC-PHASE-1-012 | I＋D008：只读评分，两客人差异；仅声明项，食材/工序要求 | customer_scorer / 旧10项评分+新v3手算、场景双客人 |
| AC-PHASE-1-013 | G：本地保存/版本/重载/重做，保留同模板多实例，不能存成绩 | recipe_library、Lane / roundtrip、坏文件/未知版本/写失败、save_load_remake场景 |
| AC-PHASE-1-014 | H＋D010/11：SAN0/30/60/100、无候选/资格/概率0/1、唯一扣除/产出 | model / SAN窗口、随机注入及重复回调测试；TEST_ONLY试锅可操作 |
| AC-PHASE-1-015 | A/J：不同结构冷菜只靠配置完整制作，不写菜名特判 | cold_salad完整场景，data_only_recipe单元；反应试锅覆盖其他机制 |
| AC-PHASE-1-016 | J：进出/重开/取消/旧输入不串，无遗留节点 | app/full kitchen / repeat_entry、cancel_reopen、无泄漏门槛 |
| AC-PHASE-1-017 | J：供料请求/真实用量记录，成品唯一事件，不改经济 | model consumed_ingredients/events，Lane→FullKitchen.dish_delivered / all_five场景及模型重复交付 |
| AC-PHASE-1-018 | 工程：同入口导入/加载/契约/单元/集成，坏门槛不误过 | tools/check.ps1、verify_gate.ps1、export.ps1；最终日志索引见PROJECT_STATE |
| AC-PHASE-1-019 | 最新用户：像素厨房行走、真实碰撞、靠灶E交互、返回 | world场景 / 5项世界测试、walk_to_stove场景、真实OpenGL截图 |
| AC-PHASE-1-020 | 最新用户：每类QTE有对应烹饪动作和可读判定反馈 | cooking_action_view / 5项场景测试、九动作与双菜实际渲染 |

执行中已修：坏配置校验自身报错、自建方案丢失实例身份、初始盘位越界、拖拽中交付、过早/晚出锅仅掉Q、快速发酵无真实等待、旧输入ID重用、界面背景文字干扰。真实鼠标通过Viewport.push_input走Godot GUI分发；直接Input.parse_input_event在headless环境未分发该GUI点击，未用直接回调冒充通过。生产拖拽使用事件坐标，避免读取滞后的系统指针。

规则边界单元测试使用显式结果夹具及固定随机源来验证算法；场景测试使用真实会话、五QTE、时钟、输入和评分，不以假分替代联调。没有经营奖励、全局库存、世界/成长线或现场存档。所有新增平衡初值PROPOSED；切型选择替代自由几何旋转按D007保留。

人工试玩与真实键鼠/音频同步PENDING/NOT_RUN。自动渲染5张完整界面、九动作图只证明能够渲染；角色为单张透明像素图配脚步/翻转，尚非四方向逐帧正式角色。UI仍是开发厨房，可继续迭代。

## 旧番茄炒蛋原型（历史验收）

> 以下为旧原型历史验收。其后范围冲突已由D013解决，完整增量和当前165项证据以上方报告为准。曾有135项中5项世界输入失败，已修复并留存历史日志；下面旧76项不能单独代表当前系统验收。

状态：ENGINEERING_READY / PLAYTEST=PENDING。2026-10-09 用户最新范围优先于旧 Phase_1.md v2，保留原文件不改。本阶段工程检查点完成，不进入Phase2。

## Grill 与产品决定

实际读取 grilling（C:/Users/Administrator/.codex/skills/grilling/SKILL.md，无版本字段）并按项目协议完成三题；GRILL_RESULT=RESOLVED。
Godot 开发读取 godot-gdscript-patterns 及 references/details.md，使用显式装配、信号、独立规则对象、静态类型。

- 自由工序；漏项可交付，明确降低菜谱完成度；无效目标、忙碌重入、交付后加工拒绝且无副作用。无经济惩罚，随时重试。
- 大块/小丁选择决定番茄细碎度；节奏品质单独决定工序品质，不按精度改变切型。
- S=0.35Q+0.25H+0.40(100-D)。仅声明要求进入 D，归一化正权重；无要求或零权重 D=0。缺必需项 Q×0.4；菜谱期待香气但完全无香时 Q×0.7、H−15。基础与需求两层分别解释，各只算一次。

## 实现前验收标准

| AC | 来源 / 输入 / 可观察结果 | 测试方式 / 状态 |
|---|---|---|
| AC-PHASE-1-001 | 用户执行内容1–2：有效少量食材/调料/两客人，7×4口味、温度、香气、三口感轴、Q、H；细碎度按食材保存；非法配置被拒绝 | PASS：5内容+13烹饪测试涵盖 |
| AC-PHASE-1-002 | Grill Q1：自由顺序有实际差异，空/漏工序可交付并解释；无效/重复/旧操作无副作用 | PASS：规则原子拒绝/重放及场景取消 |
| AC-PHASE-1-003 | Grill Q2：相同节奏不同切型改变细碎度和释放；相同切型不同精度只改变品质 | PASS：手算对照及每食材隔离 |
| AC-PHASE-1-004 | 用户执行内容3–5：节奏、连续火候、出锅真实输入；开始/完成/取消/重置明确，秒基准，暂停/失焦/长帧行为明确 | 工程PASS：13 QTE+8新场景；物理设备NOT_RUN |
| AC-PHASE-1-005 | Grill Q3：相同菜两客人得到可解释的不同分数；未声明项不扣需求分；零权重可用 | PASS：10评分手算/异常+真实顾客场景 |
| AC-PHASE-1-006 | 用户执行内容6–7：每工序前后属性可见；快照与评分只读，无重复温度/品质惩罚；独立会话无共享状态 | PASS：隔离/重复评分/温度派生+截图 |
| AC-PHASE-1-007 | 用户执行内容8：接单→加工→交付→反馈→重试在真实入口完成，无重复信号/残留状态 | PASS：真实场景、InputMap事件/信号、重复进出 |
| AC-PHASE-1-008 | 自动验收：窗口边界、重复输入、取消、非法顺序、数值范围、长帧、可复现时间线覆盖 | PASS：固定时间线、最后Good右端、10秒与6+4秒一致 |
| AC-PHASE-1-009 | 协议：同一检查入口覆盖导入/加载/所有测试，导出启动；音画与设备体验单独报告 | 工程PASS：76/76、28资源、干净副本、导出；物理音画/输入NOT_RUN |
| AC-PHASE-1-010 | 人工：玩家能根据差评改变下一次做法 | 待真实玩家试玩，不以自动测试替代 |

## 参数地位

全部新增数值均为 PROPOSED 可调原型初值，不是来源案例或已验证平衡。切菜建议8拍、0.5秒/拍、±60/140ms、品质1/0.6/0；温度与口味效果只作本菜最小映射。无星级、小费、经营或正式成就。

## 来源与冲突

大纲§3.1–3.7、§4.1–4.3、附录A/B/C支持属性/顺序效果/分层评分；Onboarding只作情境与错误反馈参考。五维标题仍保留为原文冲突，实现六项。SAN两套消耗、窗口与主线冲突本阶段不实现。番茄炒蛋缺原始运行数据，由明确标注 PROPOSED 的本阶段配置补充，不修改 towns.json。

## 实际交付与边界

- 已实现：复用TDApplication/TDClock/TDOutcome/TDSnapshot，扩展原TDCookingSession和CustomerScorer。新原型目录、真实厨房、8拍节奏、连续火力、即时出锅、两客人反馈、原型绘制与点击音轨。食材处理状态逐项保存；所有新增参数在JSON明确建议值。
- 测试替身：仅原Phase0 FixedRandom验证注入边界。Phase1逻辑测试用可注入时钟及明示结构化结果测规则；真实集成走实际QTE→会话→评分，不以伪分数替代联调。
- 未实现且不属本次范围：完整五类QTE、双菜正式版、任意反应、自由摆盘、自建食谱、SAN、单日经营/经济、雇员/分店/地图、正式美术。原型H是此菜外置关系模型，不宣称全菜系完成。
- 原始五份资料SHA256与Phase0一致；旧阶段提示不改。保留用户未提交文件；未提交/推送/对外发布、未改全局环境。

## 实際检查与证据

| 检查 | 结果 / 日志 |
|---|---|
| Phase0开工回归 | 27/27，exit0；artifacts/check/phase1-baseline |
| 最终全检查 | 76发现/76执行/76通过，531断言、0失败/跳过、exit0；artifacts/check/phase1-final，导出前另一次pre-export-20261009-130221 |
| 导入与加载 | import/load exit0，28生产脚本/场景；上述load.console.log |
| 新增覆盖 | 内容5、烹饪13、QTE13、评分10、场景8，共49项；原27项保留 |
| 干净中文空格副本 | 76/76，exit0；artifacts/gate-20261009-130257/干净 副本 |
| 检查链反证 | 正常/故意失败/跳过/解析错误/零测试/恢复退出0/1/1/1/1/0；gate-proof.json，原工程未注入故障 |
| 真实图形 | Compatibility/NVIDIA RTX3050 Laptop/OpenGL3，4张图、实际交付，exit0；artifacts/phase1-visual.json、phase1-menu/cut/paused/feedback.png |
| 音频后端 | WASAPI/48000Hz，捕获71680帧，两次瞬态0.301458/0.801458秒，间隔0.5秒，exit0无泄漏；artifacts/phase1-audio.json及日志 |
| Windows导出 | 检查后export/资源清单/独立启动均exit0；57项运行资源；artifacts/export/summary.json；build/TownDiner.exe与旁边PCK |
| 远程CI | 配置完成，共用check.ps1；NOT_RUN，无远程仓库操作 |

首轮联调真实发现：GDScript不支持%g导致运行时格式错误；已修复。自审发现并修复最终Good边界提前finish、加热跨长帧漏算冷却、暂停恢复火力显示不一致、伪造品质/剂量和过早完成漏洞；新增对应回归。音频检查首次退出存在资源释放警告，显式释放流与混音资源后复测无警告。布局首次校准行撑出窗口，已调整并重截实际画面。失败证据保留，不计为通过。

## 固定复现与命令

环境保持锁定Godot4.7.2/GUT9.7.1。原型本身无随机抽取，视觉也不消费业务随机；因此不需要隐含随机种子才能复现。

固定时间线由test_cooking_application.gd的cook函数实际执行：新会话→加入tomato/egg→cut chunk→工序相对1.0/1.5/2.0/2.5/3.0/3.5/4.0/4.5秒逐次按下/释放Space→推进0.15秒→sugar1→heat power.5持续6秒→plate。重做两份菜属性一致、会话身份不同。对应实际集成测试覆盖差做法dice+sugar3+power1，依据反馈改为chunk+sugar1+power.5，Q/需求偏差/满意度改善。

```powershell
pwsh -NoProfile -File tools/run.ps1 -Cooking
pwsh -NoProfile -File tools/check.ps1
pwsh -NoProfile -File tools/check.ps1 -Suite integration
pwsh -NoProfile -File tools/verify_gate.ps1
pwsh -NoProfile -File tools/export.ps1
```

图形复现：用锁定Godot执行`--path F:/MyGameTBD --script res://tools/phase1_visual_check.gd --rendering-method gl_compatibility --audio-driver Dummy`。
音频复现：同引擎执行`--path F:/MyGameTBD --script res://tools/audio_check.gd --audio-driver WASAPI`。它检测混音音轨，不是物理回环录音或真人同步测试。

## 人工验收与风险

PLAYTEST=PENDING，AC-PHASE-1-010未验证；当前没有人实际试玩。不宣称已验证好玩或已验证键鼠/耳机同步。图形截图、引擎输入注入和WASAPI混音捕获各自只证明对应环节。

待体验：在实际输出设备上听拍落刀，调整输入偏移；中途暂停/失焦恢复；长时间操作；根据差评尝试改善下一份。设备缓冲与显示延迟可能要求校准，当前估计不能替代物理测量。校准只保留本次应用运行，未承诺完整用户设置迁移。

全部平衡数值仍PROPOSED；“先烹饪后加料”等自由顺序可能导致未加热必需食材，会明确说明。切过的小丁不能恢复大块，重试即可。无自动经营罚款或隐藏未声明要求。

试玩不超过5步见README。本阶段工程可复用，但下一步仍是Phase1人工反馈；只有用户明确指定下一阶段才推进。
