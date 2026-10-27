# 项目状态

## D041 林夏、分店和迎宾收银传菜（2026-10-27，工程检查通过一部分，待试玩）

- 林夏在正式小镇走路，开门后进主店，最早一单用她的名字，吃完回街上。面向她按 E 对话。
- 营业牌、账本和招工处可以开分店。分店在别的小镇，现金进 Shop，一天只结一次，不计入经营等级。
- 正式餐厅未雇迎宾、传菜、收银时，由玩家招呼、端菜和送客；雇了就自动做。不第二次收钱。
- 已跑：test_town_caller 2/2、test_phase4_branch 7/7、test_shop_profiles 的开分店存档 1/1、test_restaurant_world 14/14、test_game_shell 7/7。Godot 4.7.2 / GUT 9.7.1。全量 tools/check.ps1 未跑。人工试玩 PENDING。不提交、不推送。

## D040 正式客人闭环（2026-10-27，工程检查通过一部分，待试玩）

- 用户要求把小镇功能区、餐厅装修、雇员、NPC 竞品比较和从点单到离开的订单状态做成可玩闭环。缺图用色块。
- 正式订单仍由 Shop 结算。餐厅按状态显示进门、等菜、用餐、结账和离开。装修效果按 AI-048 写入之后的选店权重，默认低档房间不改变旧权重。竞品告示能看到当日选择结果。
- 已跑：test_guest_visit 2/2、test_town_economy_rules 6/6、test_restaurant_world 12/12、test_game_shell 7/7（含三日真实后厨）。Godot 4.7.2 / GUT 9.7.1，失败 0。全量 tools/check.ps1 未跑。人工试玩 PENDING。停在本切片，不提交、不推送。

## 2026-10-27 合并上传（本地验证通过，准备推送）

- 用户授权推送；fetch得到origin/main=466b9d2，在D038/D039基线c54fc86之后新增餐厅员工及厂房交互。集成分支保留本地提交5ee38e9并合并远端，未覆盖三份未跟踪原始资料。
- 冲突逐项保留：D038-CREW与AI-046/047-CREW标注远端原编号，避免与经营等级/小屋记录混淆；保留招工入口、员工绘制及数据、四向角色、小屋休息、真实物理碰撞。日结按账本的结算标记扣员工工资，日结后支付归下个营业日，不改已结算历史。
- 员工工资/等级与跨日存读档专项18/18、518断言通过，报告artifacts/check/merge-crew-progression；合并后统一检查453/453、15186断言、693.339秒，0失败/跳过，各阶段退出0（artifacts/check/merge-habitat-crew-final）。集成到main的所有权检查通过。旧445项和旧EXE仅适用于合并前；人工试玩及远程CI待验证。

## D039移动、小屋与音乐（2026-10-26，工程就绪、待试玩）

- 四项实现已接正式入口，详见docs/phases/habitat.md、D039/AI-047。餐厅物理边界与屏幕八向同速；四向外观及朝向交互；独立小屋与床、schema4兼容旧档；三首情境BGM替换正式节拍器。保留所有D038内容。
- 最终全量445/445、15054断言、1224.274秒，0失败/跳过，所有检查阶段退出0（artifacts/check/pre-export-20261026-200517）；含本轮5项真实场景测试。GPU7图与WASAPI三曲采集、保存失败恢复通过。
- Windows开发EXE与PCK已重建，434运行资源审计、实际EXE标题启动退出3次及菜单/移动29项检查全部通过；最终artifacts/export/summary.json为PASS。音频退出残留已修正，先前失败过程如实记入habitat报告。
- AC001–007工程PASS、008人工手感/试听/设备同步PENDING，远程CI NOT_RUN。角色副本一致、所有权检查通过，写入锁释放；本地未提交、推送或合并。停在D039检查点，不自动推进整个Phase4。


## D038经营等级（2026-10-26，工程就绪、待试玩）

- 用户新授权，净利润已确认，最新纠正为店铺属性而非菜品名气。实际技能、决策及AC见D038/AI-046和docs/phases/level-progression.md。
- 已实现：按规模饱和映射的非负日XP、递增升级曲线、自动灵感、真实账本奖励页/升级提示/HUD；持久feature/furniture/story/event接入口、单包schema3、旧档不补历史。正式仅主店，多店仍为规则契约与测试，不冒称已开分店。
- 最终全量439/439、14939断言，导入/加载/测试退出0、0跳过（artifacts/check/pre-export-20261026-163552）；专项17/17，GPU6图通过。Windows开发包16:55重建，422运行资源审计、独立EXE启动及29项入口检查通过。详细AC/失败过程/试玩步骤见level-progression报告。
- 工程AC001–007 PASS；人工等级节奏/灵感平衡PENDING，远程CI NOT_RUN。角色7份文件与集成副本一致，所有权检查通过、写入锁释放。未提交、推送或合并；停在本切片检查点。
## D038-CREW 餐厅雇佣实验（远端原D038，2026-10-25，待验证）

- 餐厅招工处可雇厨师和服务员。厨师加成延长新订单等待或修正口味/口感/温度；服务员加成增加小费。入职为 1 级，数值是满级的五分之一；成功送达一单得 1 点经验，每 4 点升 1 级，最高 5 级。人数、日薪和满级效果见 DECISIONS D038-CREW 与 AI-046-CREW、AI-047-CREW（保留远端原编号）。
- 旧迎宾/收银/传菜调试岗位和小镇 NPC 工资没有替换。厨师留在后厨灶台，服务员没客人时站着，有人等菜才走过去。正式餐厅走动限制在店内可走格。专项 test_restaurant_crew 3/3；布局回归 7/7；后厨场景 6/6；服务员待命 1 项通过。全量未跑。PLAYTEST=PENDING。
- 2026-10-26：点击原料厂空地只把该地标成厂房，不重算小镇，玩家不回到地图中心。筹备或日结退出要先保存；雇员经验按 JSON 整数读回，保存失败不再把退出留在确认框里。

## D037上传交接（2026-10-25）

用户授权上传；fetch确认远端main=83888da、经济集成=3d1f138，均无新增提交。前置经济PR #3仍待审查，本轮在integration/phase-4-wave-kitchen-stock保留其提交历史后建立目标main的草稿PR，注明依赖；不自动合并main。代码与下述本地验收版本一致；新远程CI以GitHub实际运行结果为准，人工试玩仍待完成。原始未跟踪资料、artifacts和build不纳入上传。

## D037库存与熟练制作（2026-10-25，工程就绪、待试玩）

- 六项库存/烹饪反馈已授权，Grill两题已答，见DECISIONS D037；工程验收任务见docs/phases/kitchen-stock.md。
- 基线3d1f138，新的本地集成分支phase-4-wave-kitchen-stock；前序406项仅是基线证据，本轮须重新验证受影响内容。
- 已完成：已解锁菜谱主料＋全部调料供货、正式批次鲜度/FEFO/过期损耗、调味实时按量消耗/空瓶禁用、图标与四类非零冰箱、宽松判定与评分、合格手工累计400后真实自动制作。库存和手艺随槽在原日边界保存，旧档显式迁移。
- 最终全量pre-export-20261025-141250：422/422，14426断言，573.026秒，0失败/跳过；导入/加载/测试退出0。417资源导出审计、独立EXE启动、29项入口检查和GPU8图均通过。真实厨房28项、多槽/工厂14项均包含在全量中。
- build/TownDiner.exe与PCK已于14:22重建，详见docs/phases/kitchen-stock.md。AC001–007工程PASS，008人工试玩/音画设备/连续经营平衡PENDING，远程CI本轮NOT_RUN。当前仅本地变更，不推送、不合并、不扩展其他Phase4任务。

## D035–D036上传交接（2026-10-25）

- 用户授权上传经济系统新增功能与修复，并要求先检查远端。已fetch：origin/main仍为83888da，与本轮开发基线一致；原game-shell集成分支停在288af1b，没有新提交需要合并。
- 上传候选为integration/phase-4-wave-commerce，目标经集成PR进入main，本次不自动合并。协作schema2基线、已验收的装修视口G15修复分别独立提交，随后提交世界/社会经济及存档、地图接入，便于团队分别审查。
- 本次整理没有修改生产代码，复用同一最终实现的406/406、14151断言、5×360日模拟、导出headless/GPU各29项和经济GPU11截图证据。人工仍PENDING；本轮远程CI需以GitHub实际结果为准，不能用本地通过代签。
- 两份原始未跟踪商业资料保留本地，不上传build、artifacts、缓存或玩家存档。上传前补丁与状态保存在artifacts/economy-upload；推送结果与PR链接由本次交付说明记录。

## 五镇社会经济（2026-10-24，D036工程就绪，待试玩）

- 三项Grill已确认，见D036；只五镇、剧情保留接口、正利润税/自愿限额贷款/欠款继续、NPC限定商业地块扩张。AC-ECON-014–020工程PASS，021人工PENDING；本切片ENGINEERING_READY / PLAYTEST_PENDING，不代表整个Phase4完成。
- 已接入家庭现金/工资/就业/生活/储蓄、现金中介银行、公共税账、正式玩家付款/取消/退款、五镇迁移及旧已付货运、真实商业地块与施工/开业、钱庄及竞品场景交互。保留原未提交工作，未动厂商生产核心/真实存档/远端。
- 最新经济专项society-access-fourth：25/25、5731断言、42.241秒；真实入口society-game-final：7/7、164断言、151.461秒；全部0失败/跳过、导入/加载/测试退出0。涵盖真实厨房三日家庭收付款、钱庄E交互/换槽旧回调、第3天旧独立营业档导入、五镇商业区道路连通与产权保护。
- GPU最终delivery.log：11截图、退出0，真实按E查看钱庄及第14天自动购买/第17天开业的施工店告示，画面已核对。全量第一次404/405，失败交易回滚漏恢复商业标记已修复；profiles-final12/12通过。中间商业区断路失败保留日志，已增加内部步道和远镇生成连通检查。
- 最终五组×360日模拟已PASS：320户、15初始店至30店；现金/银行/库存守恒，日批处理P95 55.869–70.233ms、最大83.692ms，经济快照274605–275214字节。极高价360日零客，价格战有602439分家庭生活缺口，均没有暗中补款。结果artifacts/society-simulation/summary.json，初轮另存pre-final-summary.json。
- 最终完整回归pre-export-20261024-222400：406/406、14151断言、885.994秒，零失败/零跳过/退出0；导入/加载均通过。22:39重建build/TownDiner.exe与PCK，412运行资源审计、实际启动及隔离导出验证包headless/GPU各29项检查通过，232条餐厅可走路径阻挡0。GPU日志artifacts/society-package-gpu/run.log。
- 当前检查点完成。人工连续经营、贷款压力、扩张节奏和美术统一仍PENDING；远程CI NOT_RUN。后续应先收集三日以上试玩反馈再调平，不自动扩展剧情或下一阶段；详细能力/限制/五步试玩见docs/phases/world-economy.md。原未提交工作、源资料及真实玩家档保留，未提交推送。

## 世界经济增量（2026-10-24，D035工程就绪，待试玩）

- GRILL_RESULT=RESOLVED。用户确认自有主店免租、行为水电与欠费继续；后台全镇联动/商路分步开放；有限竞争/真实零客。仅本经济切片，不代表整个Phase4完成。来源、实际接口与AC见docs/phases/world-economy.md和CONTRACTS D035。
- 已真实接入：NPC画像/单餐意向、预算与价格/区位选择、13镇公共市场和39家竞争店、有限跨镇运输、费用/成本/欠费、正式账本和六槽schema2。旧档兼容迁移；实际厨房只增加工位秒信号，食品评分不改。厂商生产/升级经唯一钱包，建筑地图和厂商核心未改。
- 最终完整检查396/396、8685断言、557.841秒，零失败/零跳过/退出0：artifacts/check/pre-export-20261024-202311。最新经济专项16/16、305断言；真实厨房三日流程包含在全量中。锁定引擎导入/加载均通过。长期模拟3×360天/13镇通过，经济快照约89.7KB，日批处理P95约84–88ms、最大101.581ms；详见阶段报告。
- 新开发版build/TownDiner.exe与TownDiner.pck于20:32重建；406运行资源审计、独立启动和实际EXE的29项标题/存档/移动检查通过（headless与GPU各29项、退出0）。经济GPU流程7张截图、退出0；证据commerce-contract-check/visual-delivery.log。当前AC-ECON-001–012工程PASS，013人工PENDING；不宣称好玩或已完成全部Phase4。
- 状态ENGINEERING_READY / PLAYTEST_PENDING。人工经营节奏、定价体验、竞争压力PENDING，远程CI NOT_RUN。保留D034/G15原改动及原始文档，未操作玩家存档、提交或推送；停在本经济增量检查点。

## Windows重新导出（2026-10-24，已完成）

- 基于已拉取的83888da，包含四类原料厂内容；按用户要求重建build/TownDiner.exe与TownDiner.pck，生成时间18:18。运行需两文件同目录。没有提交或推送，D034本地修改和拉取备份保持。
- 修复导出阻塞：stretch/aspect=expand使视口尺寸变化，原装修栏仍固定在800高画面内，遮挡放置点击。现在跟随视口底边与宽度；未改工厂规则或经营存档。AC-G15及原点击选中/放置/删除通过。
- movement20/20、206断言；完整tools/export.ps1实际通过，pre-export-20261024-181028：41脚本、发现/执行/通过380/380/380、8377断言、444.939秒、0失败/0跳过。版本/导入/加载/测试/导出/资源清单/运行检查退出均0；393资源通过白名单。保留既有Float/Int比较warning及研习测试中的临时孤立节点提示，未出现脚本解析错误或进程退出泄露错误。
- 导出运行时独立检查：headless与NVIDIA/Compatibility图形运行各29/29，232条餐厅可走路径阻挡0。GPU日志artifacts/export/rebuild-native-gpu.log，9张截图artifacts/rebuild-native-gpu/run-1735674；已核对标题、小镇、餐厅画面。测试存档均在artifacts隔离目录，真实存档未改。
- ENGINEERING_READY；新工厂完整人工试玩、操作手感PENDING，远程CI NOT_RUN。复现：pwsh -File tools/export.ps1；局部检查：pwsh -File tools/check.ps1 -Suite movement。本次导出交付完成，停止，不推进其他Phase4功能。

## 远端同步（2026-10-24）

- 用户仅要求拉取GitHub新增内容。已fetch并将当前integration/phase-4-wave-game-shell从288af1b快进到origin/main的83888da，新增“四类原料厂可点生产，并在正式小镇里显示”；没有推送或修改远端分支。
- 原D034未提交管理改动已恢复；17个本地文件有独立副本，已跟踪改动另保留stash。除两个文档自动合入远端新增内容、Git规范化部分换行外，本地文本不变；原始资料保持未跟踪且未改。备份索引：artifacts/pull-latest-backup.json。无未解决冲突。
- 基础验证：锁定Godot版本/导入/脚本场景加载退出0；movement专项19项中18通过、1失败，200/201断言，16.507秒，退出1。失败为test_restaurant_world.gd:150的装修点击放置数量预期15/16；四项真实跨房间移动测试通过，232空地路径阻挡0。证据artifacts/check/pull-83888da-movement-native。此前受限环境的证书/编辑器缓存错误记录在pull-83888da-movement，不计通过。
- 本次没有修改远端玩法或删除失败用例；未运行完整工厂验收、全量回归或人工试玩，导出exe/PCK未重建。远端来源记录原样保留，新增厂商规则与D033经营账的接入需在后续开发中审查，不因本次拉取自动判定整合验收完成。

## D034三人协作管理（2026-10-24，本地配置完成）

- 用户确认：建筑、原料厂商、小镇经济三人并行；最后一项不是贸易。已细分active_roles=building/supplier/town-economy，保留旧角色检查兼容；只登记独占目录及既有文件，不创建玩法空模块。
- 手册第0节明确重叠函数唯一写入者、提供方先合/调用方同步、共享入口和存档由集成者接入、每天同步与小PR；工作单/PR模板增加前置基线和重叠文件。经济报价/产能具体规则仍PROPOSED，未采纳未跟踪商业原稿为正式玩法。
- 协作工具隔离Git验证：PowerShell7为22/22（artifacts/collaboration-tests/0f9deb87f6334ebcb5d0c4fe836b0282）；Windows PowerShell5.1为22/22（a578d6e1bc6f4476bdfffb718974ff1c），均退出0。包含正确/错误所有权、共享入口和存档拒绝、跨线误改、错误PR目标、不识别分支、重叠glob、UID、旧角色/schema和Init无写入预演。中间发现的测试函数重名、5.1执行策略/UTF8及Git警告混入路径问题已修复，失败输出保留。
- 此次仅工具/配置/文档变动，未重跑游戏全量或人工试玩。新版协作CI配置完成、尚未推送运行；2026-10-24只读查询确认旧PR #2（288af1b）游戏/所有权CI均成功，但PR仍为草稿未合并，main仍a164b1c。
- GitHub当前无main保护/ruleset/CODEOWNERS；保护设置为明确建议，未改远端权限。成员账号和轮值集成者映射待补。未提交/推送本次管理修改、未创建新玩法波次，未动两份原资料或玩家存档；共享文档/工具锁释放。

## D033上传交接（2026-10-23）

- 用户已授权上传本次新增功能与修复，并要求先检查远端。已执行fetch，origin/main仍为a164b1c，与开发基线相同，没有远端新提交需要合并。
- 本次提交范围为统一游戏入口、多存档、场景/市场交互、像素资源、标题入口与餐厅碰撞修复及对应验证/记录。上传目标为integration/phase-4-wave-game-shell，按协作规范经集成PR进入main；本次未授权直接合并主分支。
- 复用同一最终代码的378/378测试和实际导出headless/GPU各29项证据，详见下方记录；本次仅新增上传记录，无生产代码变动。人工PENDING，远程CI待GitHub实际运行结果。两份未跟踪原始资料继续保留本地，缓存、build、artifacts与玩家存档不提交。

## D033餐厅移动反馈（2026-10-23，已交付本地）

- 已复现176条被隐藏厨房/小镇挡住的餐厅路径，以及空功能区禁行。已隔离各场景碰撞层，按实际家具占用通行，并对齐人物脚底/家具占地显示。
- ENGINEERING_READY / PLAYTEST_PENDING：专项19/19、201断言；最终全量378/378、8318断言、492.291秒，0失败/0跳过，pre-export-20261023-204745，版本/导入/加载/测试退出均0。232条相邻空地路径全部畅通，家具拆移/墙体/反复进出/真实输入/暂停均覆盖。
- Windows导出/393运行资源审计/启动通过；导出检查驱动的文本转换错误曾被拦截，修正工具后仅重跑受影响的打包及实际程序输入检查，headless和GPU各29/29、退出0，生产包未改。最终9张GPU画面已核对，artifacts/movement-native-gpu/run-1763109；完整失败及重跑证据见game-shell.md。
- build/TownDiner.exe与PCK更新于20:56；人物落脚和家具遮挡同步修正。G12/G13及G14自动部分PASS，人工PENDING、远程CI NOT_RUN。town19项所有权及integrator75项拓扑检查通过，共享锁释放。未改玩家存档、未提交推送，停在本次修复交付点。

## D033入口反馈修正（2026-10-23，已交付本地）

- 已复现旧导出缺少食材运行依赖，空槽创建失败；此前标题启动成功不足以证明可新建游戏。根因、失败日志与AC-G09–G11见game-shell.md文末。
- 已修复运行索引/打包、初始化失败保护、进度与错误反馈；开始游戏直入最近有效档，无档自动新建，载入菜单保留选槽/另建。
- ENGINEERING_READY / PLAYTEST_PENDING：专项6/6、608断言；最终全量374/374、8272断言、691.992秒，0失败/0跳过，pre-export-20261023-193931，版本/导入/加载/测试退出均0。
- 最新Windows导出393资源白名单通过；实际导出程序的隔离鼠标创建/保存/最近载入/指定载入23项检查通过，headless与Compatibility/NVIDIA图形模式均退出0。GPU四张截图已核对，日志artifacts/title-native-after-gpu.log。build/TownDiner.exe与PCK已更新；工具驱动不在交付包内。
- G09–G11自动验收PASS，人工试玩PENDING、远程CI NOT_RUN。economy所有权13项及集成拓扑通过，角色新增核心文件哈希一致；共享锁已释放。玩家档/原资料未改，无提交推送；停在本次反馈修正交付点。

## 当前工作：D033 统一流程与多存档（2026-10-23）

- 用户Grill已确认：集市现货即到，营业中禁止离店采购。沿用筹备/日结保存边界；入口/AC/断点见`docs/phases/game-shell.md`，不是整个Phase4交付。
- 已实现：正式标题菜单、6槽档、新档门外出生、Town↔Restaurant↔原Kitchen、集市现货与原供货时点、营业牌菜单/售价、账本/休息/装修/研习物件、控制台后门、完整候选研究与经营同槽保存、旧档显式导入、像素街景/家具与音量/窗口设置。
- ENGINEERING_READY / PLAYTEST_PENDING：全量368/368、7659断言、0失败/0跳过、625.244秒，artifacts/check/pre-export-20261023-184702；最后UI输入修正再跑6/6、124断言、124.168秒，game-shell-input-final；版本/导入/加载/测试退出均0。旧研究测试1条数值类型警告和队列释放提示完整保留，不是失败或跳过。此前解析错误、600秒超时、366/368中间失败均保留为FAIL，见阶段报告。
- Windows开发导出、392运行资源白名单审计、隔离目录程序启动退出均0；build/TownDiner.exe与PCK已更新。Compatibility/NVIDIA真实GPU12张画面退出0；存档专项12/12已并入全量。未进行真人设备、音画同步和连续经营疲劳验收，远程CI NOT_RUN。
- 原350项前序证据保持历史；本轮保留未跟踪原始资料，不碰玩家真实档、不提交/推送。旧员工/分店/世界客流试验仍可从独立debug入口运行，未声称已接入新正常营业环。人工玩法与设备验收PENDING。
- 角色所有权cook2/economy9/town16、集成分支拓扑检查通过；核心文件与各工作树逐字节一致。共享锁释放，停在D033本地交付点，下一步先试玩并反馈，不自动开始下一阶段。

## 当前整合：研习功能上传与远端小镇建设（2026-10-22）

- 用户授权提交/上传。本地研习d004657已在集成工作区合入origin/main的262c86d；原始资料两份未跟踪文件不纳入提交。交付通过集成分支→main的草稿PR，未经审查不自动合入主分支。
- 双方玩法代码自动合并；DECISIONS/PROJECT_STATE顶部冲突保留双方章节。重复的远端D030用D030-TOWN别名区分，历史来源/决定保留。
- 合并后研习专项24/24；小镇/建设/访问22/22、4014断言。最终统一全量350/350、7421断言、0失败/0跳过，458.739秒，artifacts/check/pre-export-20261022-123120；版本/导入/加载/测试退出0，Windows导出/374运行资源审计/启动退出0。此前D032的7831断言属于合并前版本；远端新地图及其测试原样保留，未删测。
- ENGINEERING_READY / PLAYTEST_PENDING。人工小镇建设体验和研习手感仍待试玩；远程CI以PR实际状态为准，不把本地结果当远程通过。锁定引擎与GUT未升级。

## 当前检查点：D032 连续重试与前置线（2026-10-22）

- 两项修改已接入真实入口：失败结果立即免费重试；研习暂不消耗每日时间额度，旧时间已耗尽的进度可继续。连线分轨避让文字、选中高亮直接前置并标箭头；已掌握关系独立显示。
- 研习专项24/24、0失败/0跳过，导入/加载/测试退出0，artifacts/check/d032-research-first；最终补旧结果回调隔离的真实场景用例1/1、27断言；GPU实际渲染17张、exit0。
- ENGINEERING_READY：最终全量350/350、7831断言、0失败/0跳过，36测试脚本，418.828秒；版本/导入/加载/测试均退出0，artifacts/check/pre-export-20261022-115956。Windows导出、374项资源清单审计、程序启动均退出0，artifacts/export/summary.json；build/TownDiner.exe和PCK已更新。
- R11/R12自动验收通过，人工设备/手感PENDING、远程CI NOT_RUN。原始资料与真实存档未动，无提交/推送。共享锁已释放，停在本轮研习修正检查点，不自动进入其他Phase4功能。

## 历史检查点：D031 研习修正（2026-10-21）

- ENGINEERING_READY / PLAYTEST_PENDING。四项已交付：正确空心选择框与前置线、真实厨房操作研习、B键原场景覆盖层、锁菜系禁止浏览。
- 347/347测试、7605断言、0失败/0跳过；导入/加载/测试退出0，证据artifacts/check/pre-export-20261021-144032。专项规则10/10，真实研习场景11/11包含在全量中；真实GPU截图12张通过。Windows包374资源审计/导出/启动退出0，artifacts/export/summary.json。
- 初次导出漏列research_lesson.gd被启动检查抓到；仅修正导出清单后复用原导出/审计/启动步骤重跑通过，规则脚本未改。中间主动中止的全量不计通过。
- 两个可研习关卡仍是阳春面、蒸水蛋，80分/永久资格/完成1小时保留。训练SAN=100，窗口/判定/操作直接来自厨房；原始用户资料未动。
- 主动打开书暂停底层，返回恢复原状态；营业只能查看，筹备/日结可以研习，新学菜即时加入当前菜单。正式剧情、其余98关与完整Phase4未实现。
- 当前停止于D031交付点。真实物理输入、听觉同步、难度与乐趣PENDING；远程CI NOT_RUN；没有提交或推送。build/TownDiner.exe与相邻PCK已更新。

## 历史检查点：D030 菜谱研习初版（2026-10-21）

- 已实现：参考HTML五菜系100节点的原生竖树、前置连线、纸质详情、搜索缩放定位；C01蛋炒饭/C02番茄炒蛋起步；灵感永久资格；C03阳春面/C04蒸水蛋两张真实四轨关卡；80分解锁；独立保存、剧情推荐/灵感事件幂等接口。
- 经营接入：新菜可进入现有厨房和菜单；三道新增运行菜已实际采购/制作/交付。旧经营档合法解锁继承，不恢复旧60分和Perfect生产绕过。菜单读档保持玩家原启停选择。
- 范围：仅D030用户授权切片，不自动执行完整Phase4；其他图谱节点可浏览但无谱面时不能购买。正式剧情事件、熟练度、完整世界存档未做。原始文档只读，旧源文件未动。
- 当前验证：最终统一全量343/343、7606断言、0失败/0跳过，导入/加载/测试退出0；研习专项17/17、三道菜真实流程1/1、GPU实际渲染8张通过。Windows开发导出/372项资源清单审计/导出程序启动均通过，见recipe-study.md；第一次300秒全量超时保留为中间失败记录。
- PLAYTEST=PENDING：真实键鼠/耳机延迟、听觉同步与挑战难度待用户试玩；无机器模拟替代好玩结论。未提交、未推送，既有两份未跟踪用户资料保留。
- 已停在本轮研习工程检查点。后续可按真实试玩反馈补谱或接剧情推荐，需用户继续指定，不自动推进其他Phase4内容。

## 历史检查点：D030-TOWN 小镇建设区重划（2026-10-13）

- USER_CONFIRMED：餐厅建设区空地点击建主店；8 个原料厂空地点击建厂，不用 E。
- 地图开局不再自动放主店。`diner_lot` + 8×`factory_lot` 固定生成；建成后为 `player_diner` / `supply_factory`。
- 已改 `town_map.gd`、`phase3_session.gd`、`town_world.gd`、`phase3_world.json` 与相关单测期望；契约见 CONTRACTS D030-TOWN，决定见 DECISIONS D030-TOWN。
- GRILL_SKILL=NOT_AVAILABLE。本机未找到锁定版 Godot，定向 GUT 与 `tools/check.ps1` 记 NOT_RUN。PLAYTEST=PENDING。
- 可玩：走进小镇 → 点击餐厅建设区，选择中餐厅或西餐厅。建成的店只占建设区四分之一，走到店上就进入店内。点击原料厂空地建厂，再点厂房安排生产；面板显示正在生产的进度，完成后从底部「背包」查看一级原料。小镇底栏只留返回和背包。功能区与菜市场仍用 E。
- 下一工作单元：本机装回锁定 Godot 后跑 `test_phase3_rules` / `test_phase4_branch`；人工试玩建设手感。不自动提交。

## 当前检查点：D029 三人合作框架（2026-10-13）

- 已建立三条固定工作线、轮值集成者、角色分支→集成分支→`main` 的两级合并方式，以及文件所有权、共享锁、工作单、契约、交接、审查、合并日和完成定义。
- 可执行入口是 `tools/collab.ps1`，机器配置是 `collaboration.config.json`，操作规范和当前看板分别是 `docs/collaboration/README.md` 与 `docs/collaboration/CURRENT_WAVE.md`。PR 模板和 GitHub 分支拓扑/所有权检查也已接入。
- Windows PowerShell 5.1 实测：`Validate` 退出 0；Phase 4 第 0 波 `Status` 退出 0 并只列出预期分支/路径；角色 PR→同波集成分支、集成 PR→`main` 的正路径退出 0，角色 PR→`main` 按预期退出 1；用 `cook` 身份检查当前共享改动也按预期逐项报告越权。
- 当前波次为 `IDLE`。现有工作区有未提交修改，`Init -WhatIf` 按预期退出 1，因此没有运行实际 `Init`，也没有创建分支、工作树、提交或 PR。Phase 4 仍未开工。
- 本检查点没有改 Godot 玩法，没有运行 `tools/check.ps1` 或人工试玩；历史测试结果不变。下一步是在用户授权 Phase 4 且形成干净基线后，由轮值集成者填写工作单和共享锁，再预演并初始化工作树。

## 当前检查点：D028 Phase 1–6 完整方案（2026-10-13）

- 已按“1013 会议优先、设计大纲其次、模糊处用编号 AI 填充”的规则重写 Phase 1–6 方案。
- 总入口：`docs/FULL_IMPLEMENTATION_FLOW.md`。逐阶段执行：`doc/agent_prompts/Phase_1.md` 至 `Phase_6.md`。AI 默认方案：`docs/AI_FILLED_DETAILS.md`。
- Phase 1、2 保留历史工程基线；Phase 3 仍按小组口径开发完成，人工试玩 `PENDING`。下一阶段是 Phase 4 的三波改造，尚未开工。
- 本检查点只改文档，没有改玩法代码，没有运行新的 Godot 测试或 `tools/check.ps1`。历史测试结果不变。
- 下一工作单元：用户明确开始 Phase 4 后，执行 Phase 4-0 契约、红灯和世界存档迁移；未获授权时停在方案。不自动提交或推送。

## 当前检查点：D027 会议后方案（2026-10-13）

- 小组确认 Phase 3 开发完成。本检查点只改方案，没有改玩法，也没有新的测试。PLAYTEST 仍是 PENDING。`tools/check.ps1` 没有为这次改文档重跑。
- 已落地的范围仍以 D021–D026 为准，包括斜角餐厅、小镇客流、SAN 调试、营业时间、一家分店、入座和传菜。
- 10 月 13 日会议修订的是下一阶段：低 SAN 改为入锅换做法，岗位收成服务员、厨师、店长，之后做研发、食谱图、市场、调料、店种、市政划区、猪瘟和禽流感。低 SAN 小镇和章节主线不排进这三波。
- 下一工作单元：按 `docs/phases/plan-1013.md` 先写契约，再三人并行。没有开工授权时停在方案。不自动提交。

## 当前检查点：D026 入座与传菜（2026-10-12）

- 客人等菜和吃饭时坐在座位上。做好的菜放在门口里侧的传菜口。玩家按 E 端到那一桌，或雇传菜员自动端。传菜员日薪 7 元。PLAYTEST=PENDING。`tools/check.ps1` 仍 NOT_RUN。
- 可玩：餐厅里雇迎宾和传菜员，点「全程来客」。客人坐下后，去后厨做出他点的菜，回餐厅看传菜员把菜端到座位上。不雇的话，自己走到传菜口按 E，再走到座位旁按 E。
- 验证：Godot 4.7.2.stable.steam.ed1daf0bf，GUT 9.7.1。`test_floor_service`、`test_phase3_visit`、`test_restaurant_world` 共 20 项、159 断言，0 失败。

## 当前检查点：D025 餐厅与后厨同一条客单（2026-10-12）

- 全程客人的点单、等待、上菜、超时和后厨出盘是同一张单。站在餐厅门口按 E 进后厨，后厨门口或「回餐厅」回来。V 只看餐厅，时间继续。PLAYTEST=PENDING。`tools/check.ps1` 仍 NOT_RUN。
- 可玩：走进小镇，进餐厅，雇迎宾后点「全程来客」。菜单上有的菜，客人坐下后出现在后厨右侧。做出对应的菜会端给最早在等的那一桌。
- 验证：Godot 4.7.2.stable.steam.ed1daf0bf，GUT 9.7.1。`test_floor_service` 4/4，`test_phase3_visit` 5/5，`test_restaurant_world` 9/9，共 18 项、124 断言，0 失败。

## 当前检查点：D024 规模维护、工资、情绪与性格（2026-10-12）

- 维护费按餐厅占地增加。雇员工资可以加减；高于推荐值会提高服务质量。情绪和懒惰/勤奋、马虎/认真也会改服务质量和事故概率。相关测试 19 项、4378 条断言通过。PLAYTEST=PENDING。`tools/check.ps1` 仍 NOT_RUN。
- 可玩：小镇里点「看员工」「工资+1」「工资-1」。换天或结算分店时会看到维护费。

## 当前检查点：D023 餐厅面积、雇员与一家分店（2026-10-12）

- ENGINEERING_READY 仅限本轮规则和入口；PLAYTEST=PENDING。主店在中心路口旁边，默认 3×4。店内面积随占地变大。非主小镇可以划地，同时只开一家分店。备菜、主厨、店长和原来的迎宾、收银、保洁按日薪分工。
- GRILL_SKILL=NOT_AVAILABLE。没有安装。假设见 D023。
- 可玩：走进小镇后，主店色块在路口旁边。选面积后可以改主店，或到巴黎这类非主小镇，站在空地左上角划分店。雇备菜、主厨、店长；教会当前菜；备菜岗动手和主厨出菜会扣仓库原料。分店单独备货、结算。同一天再点结算不会多给钱。
- 验证：Godot 4.7.2.stable.steam.ed1daf0bf，GUT 9.7.1。`test_phase4_branch` 3/3，`test_phase3_rules` 12/12，`test_phase3_visit` 2/2，`test_restaurant_world` 8/8，共 25 项、4391 断言，0 失败。`tools/check.ps1` 本机没有 pwsh，NOT_RUN。人工试玩 PENDING。
- 下一工作单元：按试玩看划地是否好找、主厨接手是否清楚、分店日结是否读得懂。不自动提交。

## 当前检查点：D022 六座小镇、SAN 与营业时间（2026-10-12）

- ENGINEERING_READY 仅限本轮规则和入口；PLAYTEST=PENDING。用户指定六座小镇、中心餐厅、随机四向道路、可调试 SAN、阴暗菜、营业时段和功能区互动。
- GRILL_SKILL=NOT_AVAILABLE。本机没有 grilling 与 godot-gdscript-patterns，没有安装。GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS。假设见 D022。
- 可玩：主菜单进小镇。餐厅在道路中心，四条路长短随机。开局可改 SAN 和开关门时间，然后开始营业、收摊、去休息。E 选定菜市场或查看功能区，花时间和钱回复 SAN。低 SAN 进入原厨房时判定窗变窄，画面变暗，准备阶段可能短暂显示错误音符。SAN 低于 30 且番茄炒蛋评分达到 80，有概率学会西红柿炒皮蛋。
- 验证：Godot 4.7.2.stable.steam.ed1daf0bf，GUT 9.7.1。`test_phase3_rules` 12/12，`test_phase3_visit` 2/2，`test_restaurant_world` 8/8，断言 4217，0 失败。`tools/check.ps1` 本机没有 pwsh，NOT_RUN。人工试玩 PENDING。
- 下一工作单元：按试玩看道路是否太绕、SAN 掉得是否太快、假判定是否干扰读谱。不自动提交。

## 当前检查点：D021 斜角餐厅与小镇客流（2026-10-11）

- ENGINEERING_READY 仅限本轮框架；PLAYTEST=PENDING。用户授权 Phase 3 的餐厅、小镇、菜谱解锁、延迟进货和 NPC 全流程。官方 Phase_3 提示里的低 SAN 实验、成就和音量重绑定这次没做。
- GRILL_SKILL=NOT_AVAILABLE。本机没有 `C:\Users\25293\.codex\skills\grilling\SKILL.md`，也没有 godot-gdscript-patterns。没有安装。按协议做了等价审查，GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS。假设见 D021。
- 可玩：主菜单进小镇，沿上下左右的路走，E 看市场、竞品和功能区；进斜角餐厅，雇迎宾和收银会扣工资。全程来客会走迎宾、点单、入座、等上菜、吃饭、收银、离开。菜单外的菜可拒绝或接下。学会后点「去厨房」，在原来的营业厨房按谱做。客流面板显示预算分布、选店、装修效果、口碑、开支和到货。「备料」按一道菜或点选一种食材入库，设备延长保质期，过期在下一天清掉。
- 规则：评价公式按经济草稿。总体评价达到 60 才解锁。今天订货默认明天到；流水线或近市当天到。下一天扣租金、水电和设备维护，在岗员工再付一天工资。功能区改变人数、预算平移和外来偏好，关掉一个区人数会变。十三座小镇用用户给的昵称，能对上 towns.json 的菜保留原文 id。
- 验证：Godot 4.7.2.stable.steam.ed1daf0bf，GUT 9.7.1。`test_phase3_rules` 11/11，`test_phase3_visit` 2/2，`test_restaurant_world` 8/8，断言 1897，0 失败。`tools/load_check.gd` 仍是上一轮的 resources=65 failures=0。画面 `artifacts/restaurant-play.png`、`restaurant-edit.png`、`restaurant-guest.png` 是上一轮截图。`python tools/kenney_fetch.py search --query furniture --pages 1` 列出 Furniture Kit 等 3 条。
- 全量 `tools/check.ps1` 本机 PATH 没有 pwsh，NOT_RUN。物理键鼠和人工试玩 PENDING。新菜的逐拍表复用现有炒/蒸谱，主料是厨房里已有的组合。小镇贴图是色块，餐厅贴图是程序绘制的菱形。
- 下一工作单元：按试玩反馈改斜角手感、客流公式或每道菜自己的拍点。不自动提交。

## GitHub同步：D019–D020交互改进（2026-10-10）

- 用户已明确授权将本轮修改提交并推送到既有仓库CRYCHIC-Saki/GameNameTBD；目标沿用main，本地codex/phase1-upload，使用既有项目作者信息，正常追加提交，不改写远程历史。
- 推送前实际获取origin/main，与本地基线d08470e一致。439个工程输入与最终281/281通过的无缓存副本指纹一致，六份原始资料未改。本次仅增加同步记录，不改变已验证玩法。
- 提交包含D019自动订单/环形长按调味、D020自由备菜/冷藏取回/探索解锁/失败菜、测试、Godot UID及文档；缓存、测试产物和Windows导出包继续按.gitignore排除。不创建正式发行版。
- 远程CI实际结果以对应提交的[GitHub Actions](https://github.com/CRYCHIC-Saki/GameNameTBD/actions)为准，本地通过不代替远程通过。下方未提交/未推送为本地交付时历史；实体设备和玩法验收仍PENDING。

## 当前检查点：D020 自由备菜与探索菜谱（2026-10-10）

- ENGINEERING_READY；PLAYTEST=PENDING。本轮三题已确认并完成AC-PHASE-2-020–025自动验收；继续Phase2，不进入Phase3。技能实际使用来源及决定见DECISIONS D020。
- 可玩：三单材料/要求卡→任意主料自由取用→菜板选择切型并打谱→E放锅/F开始炒或蒸/Q开火前逐件取回→调味明确按下/保持/松开→端盘交付或垃圾桶丢弃。错误放料可纠正，手中原料和切配品可回冰箱冷藏，保留身份与实际处理结果。
- 五道初始菜保持解锁；新增锁定汽锅鸡，鸡肉+菌菇蒸制、必需项与全部计分工序Perfect才解锁，边界存档保留。未知组合复用完整流程及自由长按调味，最终失败菜；误送匹配全队首客，负评与建议人气−4幂等执行，无收款。
- 最终全量281/281，28套件2679断言，0失败/跳过，导入/加载/测试exit0：artifacts/check/pre-export-20261010-173454。Windows包build/TownDiner.exe＋同目录PCK已更新，103项资源白名单及独立启动通过，artifacts/export/summary.json。
- 干净副本artifacts/d020-clean-20261010-173551/干净 副本再次281/281、exit0，未复制.godot缓存；439个工程输入与最终工作区逐字节一致。汇总artifacts/d020-delivery.json。
- GPU真实渲染37张截图、输入及交付/保存/继续/解锁/失败/垃圾桶通过，artifacts/d020-visual.json及d020-gpu-exit.json，exit0。不是实体键鼠操作；设备音画同步NOT_RUN、可读性/手感/三日疲劳PENDING。
- 六份原始资料指纹全部不变，artifacts/d020-source-verification.json；隔离测试存档，不改真实玩家档。引擎及依赖锁未升级。建议来客基数45秒、初始预估6–10人，保持最多3单，平衡未获人工验收。
- 本轮未提交/推送，远程CI为NOT_RUN。下一工作单元为README/PLAYTEST的五步试玩与具体反馈修复；在当前阶段交付点停止。下方D019/旧版本记录仅供追溯。

## 当前检查点：D019 交互修改（2026-10-10）
- 本轮四项交互及后续明确答复已实施；仍是Phase2，不进入Phase3。无阻塞产品问题，实际技能与参数来源见DECISIONS D019。
- 可玩路径：筹备页看预计访客范围→大冰箱任意拿料→按最早同菜客人要求备菜/烹饪→环形长按调味→端盘自动匹配出餐→日结/保存/继续。订单卡无接单、分锅、取消或售罄按钮；不同菜可乱序完成。
- 同主料/工序以基础菜品身份识别，甜口/咸鲜/小丁为顾客要求。小丁密集谱与长糖料目标真实生效，不替换实际失误结果。自建做法及旧边界存档兼容。
- 模型提交前整笔扣实际材料，搬运不重复扣；锅和散料只分配一次。确实缺料订单自动谢客、人气建议−1并有反馈；超时不删除食物。收款改为交付时发生，旧手动接单路径已移除。
- ENGINEERING_READY；最终检查266/266，27套件，0失败/跳过，导入/加载/测试均exit0。证据artifacts/check/pre-export-20261010-144418；Windows包已更新、103项运行资源、导出/白名单/启动exit0。
- 无缓存中文空格副本artifacts/d019-clean-20261010-144803/干净 副本再次266/266，437个工程输入与工作区逐字节一致。真实GPU24张截图已验证交付、保存与继续到第2天；物理设备NOT_RUN、真人手感PENDING。
- 本轮未提交、未推送；远程CI未运行。下面GitHub/247项等为旧版本历史，不能代替当前验证。
- 下一工作单元：用户按README/PLAYTEST试玩本阶段，再修具体反馈；本次工程交付完成后停止，不自动推进下一阶段。

## GitHub同步：Phase 2（2026-10-10）

- 用户明确要求将新增内容上传到既有仓库 `CRYCHIC-Saki/GameNameTBD`。目标沿用 `main`，使用本地 `codex/phase1-upload` 分支和既有本地作者信息，正常快进推送，不改写远程历史。
- 上传前已获取远程main，确认与本地基线 `14e64e2` 一致。429个工程输入文件与最终247项通过的无缓存副本逐字节一致，六份原始设计资料指纹不变；本次同步仅更新交付记录，不改动已验证玩法。
- 提交包括代码、内容、测试、Godot UID、工程配置及阶段文档。缓存、测试产物和Windows导出包按现有.gitignore排除；不创建正式发行版。
- 远程CI由推送触发，实际结果以本提交的[GitHub Actions](https://github.com/CRYCHIC-Saki/GameNameTBD/actions)为准；以下NOT_RUN/未推送描述为本地验收时状态，不代替远程执行结果。人工设备与玩法验收仍PENDING。


## 当前检查点：Phase 2单店连续营业（D017，2026-10-10）

- ENGINEERING_READY；PLAYTEST=PENDING。用户已授权Phase2并确认营业节奏、应急继续策略、筹备/日结边界存档。复用Phase1 D015/D016，不重建做菜、不进入Phase3。
- 实际可玩：五道审核菜采购/菜单/定价→自动到客与耐心→指定左右锅→食材架E取料→菜板按谱→搬入锅自动QTE→实体端盘出餐→真实顾客评价/收支库存日结→下一天。可售罄/取消/提前打烊；次日资金不足可条件式主动领补助。
- 真实规则：整数分/毫份、整笔采购与预留、实际累计消耗、未用释放/已用损耗、订单/成品身份和幂等结算。人气、每菜名气、店名气分别启用；声望独立DEFERRED。业务事件边界注入厨房推进，超时后不晚扣料。
- 自建做法：保存真实完整食材与工序方案、稳定ID/版本、改名、加入菜单并按实际调味顺序重做；不保存高分。未知/不支持的顺序、缺项方案明确拒绝，不改回基础谱冒充成功。自建番茄菜仍保留原客人切型要求。
- 存档：仅筹备/日结；user://shop-v1.json。临时写/读回语义与摘要校验/备份/替换；真实半写及中断恢复测试，未知版本与坏档不静默覆盖。开门前和进入下一天前保存边界，营业中返回或关窗口提示回退；不恢复QTE现场。
- 最终全量：artifacts/check/pre-export-20261010-122915，247发现/执行/通过，26套件、2218断言，0失败/跳过；版本、导入、49资源加载、测试均exit0。新增28项，原219项保留回归。
- 最终干净副本：artifacts/phase2-final-clean-20261010-123109/干净 副本/artifacts/check/final，同一检查入口，无.godot缓存、中文空格路径，247/247通过。最终输入文件与工作区逐字节一致，见artifacts/phase2-delivery.json。
- 门槛证明：artifacts/gate-20261010-122441/gate-proof.json；clean/restored exit0，故意失败/必测跳过/解析错误/零测试 exit1。门槛复制后补自建顾客继承修正，再以最终全量/导出与新干净副本验证，不混用旧副本宣称最终代码。
- 图形：artifacts/phase2-visual.json及22张phase2-*.png，真实NVIDIA RTX3050/Compatibility，Viewport输入完成交付、自建保存、存档继续到下一天，exit0。已查看并修复厨房背景层级、采购排版、弹窗和反馈文字。物理键鼠/音画同步NOT_RUN；人工连续营业疲劳及好玩程度PENDING。
- 导出：build/TownDiner.exe＋同目录PCK已更新，artifacts/export/summary.json，export/pack-manifest/smoke exit0，103项允许运行资源。运行内容排除GUT/测试/工具/原设计/独立dev入口。当前为开发演示，保留明确允许的旧兼容代码。
- 来源/边界：docs/systems/business.md与phases/phase-2.md；五菜名字有原文，精确矩阵、价格、份量、节奏和平衡均PROPOSED。六份原始资料SHA256全部一致，artifacts/phase2-source-verification.json。测试只写隔离artifacts，不改真实玩家存档、引擎依赖或全局环境。
- 本地验收完成时未提交/推送，远程CI为NOT_RUN；后续用户授权GitHub同步见上节。Git基线14e64e2，保留本地codex/phase1-upload。历史远程记录见下方。
- 下一工作单元：按README五步和PLAYTEST连续手工经营3天，记录压力、重复感、价格反馈与存档理解；在Phase2内修具体问题。无新的阻塞产品问题，不自动开始下一阶段。


## GitHub 同步：D016（2026-10-10）

- 用户在本轮明确要求将D016修复推送到既有仓库`CRYCHIC-Saki/GameNameTBD`的`main`；沿用本地`codex/phase1-upload`分支、既有作者信息与正常快进推送，保留远程历史。
- 推送前远程main与本地基线7d448c7一致；16项有改动的代码/配置/测试/工具文件与最终219项通过的干净副本逐一校验相同。缓存、检查产物和Windows导出包继续排除在提交之外。
- 远程CI实际结果以本提交的[GitHub Actions](https://github.com/CRYCHIC-Saki/GameNameTBD/actions)为准；下面的NOT_RUN和未推送描述为D016本地验收时的历史状态，不能替代远程结果。实体设备与人工试玩仍PENDING。

## 历史检查点：Phase 1 菜谱打谱与反馈修复（D016，2026-10-10）

- ENGINEERING_READY；PLAYTEST=PENDING；仍为Phase1。用户最新决定已覆盖D015自由转向/六刀示例以及调味同时控温的安排；没有推进经营或Phase2。
- 实际实现：切菜从菜谱读取“落刀/转向”谱，番茄当前为Space→D→Space，全中得到块。错键、离拍转向不改变方向；缺失转向会使后续不符方向的刀判Miss。切型和成功落刀数保留为食材处理状态，转向不算一刀。其他切型通过配方谱配置，不添加选择菜单。
- 实际反馈：每拍显示Perfect/Good/Miss、早晚毫秒或错键/漏拍原因、音符状态，并播放不同短提示音；最后一拍后仍显示约0.9秒。暂停冻结反馈寿命，取消/重开清理。提示音生成/调用自动验证通过，不等于真人听觉验收。
- 鼠标安排：本锅控温在M6前结束；双锅任一M6进行时，另一锅显示托管并保持当前控温位置，暂时排除该段稳定度判分，不赠送成功，游戏时间继续。M6结束后恢复，等待新的鼠标控制输入。
- 时间：键盘/调味目标间隔约1秒、主要工序预告2秒。出锅先预告2秒，再给最多2秒起手等待；有效按住后独立计满2秒蓄力及松手窗口。保留50/100ms判定窗。时长属于PROPOSED，物理手感待调。
- 最终本地：`artifacts/check/pre-export-20261010-112301/summary.json`，219发现/执行/通过、23套件、1913断言，0失败/跳过，版本/导入/加载/测试均exit0。新增11项规则＋3项真实场景用例，旧205项继续回归。
- 最终干净副本：`artifacts/d016-clean-20261010-112650/干净 副本/artifacts/check/final/summary.json`，未复制.godot缓存，同一check入口导入/加载/219项测试均exit0，0失败/跳过。
- 图形：`artifacts/d016-visual.json`和22张`d016-*.png`，真实Compatibility/NVIDIA RTX3050渲染，Viewport注入键鼠、调料柜和端盘交付成功，进程exit0。已查看Perfect/Miss、调味和实际出锅长按画面。实体键鼠、耳机/扬声器音画同步NOT_RUN；可读性/手感PENDING。
- Windows包：`build/TownDiner.exe`＋同目录`TownDiner.pck`已更新；`artifacts/export/summary.json`，export/pack-manifest/smoke均exit0，94项运行资源。开发演示范围不变；没有远程推送或发布，当前修改的远程CI为NOT_RUN。
- 验收：AC037–041工程PASS，设备/人工部分PENDING。红灯测试最初6项失败；最终复检又发现3项旧自建配方测试失败，已修复其完整目录引用校验上下文，未删测试/放宽门槛。详细中间证据见phase-1。
- 六份原始资料SHA256全部一致，`artifacts/d016-source-verification.json`。保留已有工程；测试写入隔离artifacts；未改真实存档、依赖锁或全局环境。本地验收完成时尚未提交/推送，GitHub基线为7d448c7；后续同步见上节。
- 下一工作单元：依README/PLAYTEST用更新后的包实际试玩切菜反馈、调味切换、出锅晚起手与双锅托管；按反馈继续Phase1。物理设备未验不自动视为通过，不自动进入Phase2。

## GitHub 工程同步基线（2026-10-09）

- 用户已明确授权将当前工程上传到 `CRYCHIC-Saki/GameNameTBD`，目标为 `main`，保留远程初始README提交。此次仅同步工程，不创建正式发行版、不推进Phase2。
- 上传前检查：`tools/check.ps1 -ReportName github-prepush-20261009`，锁定版引擎导入/加载/测试均exit0，205/205通过，0失败/跳过；本地证据在 `artifacts/check/github-prepush-20261009/`。
- Git保留源码、素材、测试依赖、版本锁及设计资料；缓存、工具下载、检查产物和导出包不入库。六份 `doc/source/` 原文在Git暂存区与工作文件逐字节相同，已单独禁用换行转换。
- 远程CI由推送触发，实际结果以 [GitHub Actions](https://github.com/CRYCHIC-Saki/GameNameTBD/actions) 对应提交为准；下面各阶段的NOT_RUN/未推送为当时历史状态。人工试玩仍为PENDING。

## 历史检查点：Phase 1 自动工序与界面纠正（D015，2026-10-09）

- ENGINEERING_READY；PLAYTEST=PENDING；仍停在Phase1。最新用户否定D014自由菜单与地面功能位，本轮按做菜操作.md §3–7重做玩家交互，历史190项通过不代表旧体验已被用户接受。
- 实际可玩：台面番茄/鸡蛋→砧板自动M1→拿取搬入锅→E自动M2→M3下油/下料→M3∥M4→M6十格柜→M3勾芡→M7→端盘出餐。番茄蒸蛋按砧板→M6→上笼8拍→留白→出锅；炖牛肉M5可离开，常驻条跨厨房/其他工序。蒸/炖样例明确TEST_ONLY。
- 实际界面：主菜单只有进厨房/退出；工序页为动作、QTE和HUD，没有选择下一工序、份量/刀数表、拖盘、返工或配方库按钮。右上温度/细碎度格/味型环、底部共享拍条、两客人评价卡。双锅自动并列，两个温度条共用横坐标，鼠标位置与实际吸引目标对应。
- 实际规则：输入目标来自逐拍表，Rest不生成目标，允许手/鼠并行和第1拍预备拍；真实QTE完成才提交，不点材料柜不凭空加料；错料进入实际味型。M3多段先聚合再用一次模块权重。两个会话、取消/返回/重开继续使用既有身份和清理边界。
- 最终全量：205/205，22套件，1812断言，0失败/跳过；导入、45生产资源加载、测试均exit0。证据 `artifacts/check/pre-export-20261009-223812/`。本轮15项新增测试（9规则、6真实入口集成），历史190项继续回归但不代替新入口测试。
- 最终干净副本：`artifacts/guided-clean-20261009-223811/干净 副本/artifacts/check/final/`，新中文空格路径导入/加载/205测试均通过。门槛证明 `artifacts/gate-20261009-221502/gate-proof.json`：clean/restored exit0；故意失败、必测跳过、解析错误、零测试分别exit1。门槛后修双锅视觉坐标、暂停提示层级和相邻指令串预告，已以最终全量及新副本重新验证。
- 图形：`tools/guided_visual_check.gd` 实际NVIDIA RTX3050/Compatibility渲染18张 `artifacts/guided-*.png`，实际端盘交付true、exit0，无引擎错误/泄漏。真实Godot键鼠事件注入通过；实体键鼠、扬声器/耳机同步NOT_RUN，主观手感PENDING。
- Windows包：`build/TownDiner.exe`＋同目录PCK；最终导出/资源清单/独立启动均exit0，94项运行资源。证据 `artifacts/export/summary.json`。开发演示含明确TEST_ONLY样例，排除GUT/测试/原设计/工具/独立dev入口；旧兼容依赖代码保留但不从玩家菜单暴露。远程CI NOT_RUN，无推送或发布。
- AC029–036工程通过；物理设备与玩法验收未验证。技能实际来源、冲突/假设/建议值见D015；六份原资料SHA256全部一致，`artifacts/guided-source-verification.json`。测试写入隔离artifacts，不覆盖真实玩家存档。仓库原本均未提交，本轮没有Git重置/提交/推送。
- 剩余风险：6刀全中切丁与大块客人的教学取舍需试玩；新数值和原型绘制动作未作最终平衡/美术验收；蒸笼共用右锅，不能第三菜并发。M1/M5权重及文档M3/M6冲突按D015记录，可调整但不伪装成已确认平衡。
- 下一工作单元：按README/PLAYTEST在Phase1内试玩与修反馈。没有自动执行Phase2；后续经营只接既有成品/消耗边界。

## Phase 1 PC操作与搬运（D014历史检查点，界面已被用户否定并由D015替代）

- 当前范围：按doc/source/做菜操作.md实现M1–M7及料箱→菜板→搬运→灶台→端盘出餐。ENGINEERING_READY；PLAYTEST=PENDING。仍为Phase1，没有进入Phase2。
- Grill：实际读取grilling及Godot patterns，按grilling进行只读事实审查；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS。最新文档修订预选切型/旧键位，用户既有平台、暂停、自由工序和评分决定继续使用；假设/来源在DECISIONS D014。
- 已实现：真实功能位E交互；手持/菜板/双锅所有权、原子实例转移；按拍落刀/转向、扫动点火、方向翻炒、共享鼠标控温、后台炖煮、实际材料柜调味、长按蒸制/出锅；热/手两轨并行、可配置节拍表、共享BPM和循环占位音轨、辅助/校准、端盘唯一交付、方案v2保存及物理备料重做。原规则/评分继续复用。
- 全量：190/190，1706断言，20套件，44生产资源加载；导入/加载/测试exit0，0失败/跳过。最终原工程证据artifacts/check/pre-export-20261009-193001；25项新增PC测试涵盖9QTE＋9规则＋7真实场景。旧165项保留兼容验证。
- 干净副本：最终源在artifacts/pc-clean-20261009-193027/干净 副本完整导入、190/190、exit0。四种故障门槛见artifacts/gate-20261009-192500/gate-proof.json：正常/恢复190通过，故意失败/必测跳过/解析错误/零测试均exit1。
- 图形与输入：真实GPU渲染8张pc-*.png，实际交付及柜子GUI点击true，exit0，无引擎错误/泄漏；artifacts/pc-visual.json。键鼠为Godot事件注入，未代替实体设备。物理音画/输入同步NOT_RUN，手感和差评引导效果PENDING。
- 导出：Windows开发演示包build/TownDiner.exe＋TownDiner.pck；92项运行资源、导出与独立启动exit0，artifacts/export/summary.json。排除测试/GUT/原设计/工具/独立开发入口。远程CI仅配置，NOT_RUN，无推送发布。
- AC021–027工程通过，AC028工程通过/人工待验；详细映射、实际文件和中间失败修复见phases/phase-1.md。README/PLAYTEST已改为当前搬运和按拍操作。
- 风险/边界：新增数值PROPOSED；两刀形态/鼠标吸引等假设可回退。单手单菜板、无限原型供料，蒸笼共用右锅；界面/功能位/动作/音轨仍为原型。旧批次/保温/SAN测试控件不在PC界面，模型保留。经营与完整SAN成长未实现。
- 六份源资料SHA256均未变化，artifacts/pc-source-verification.json；测试文件均在隔离artifacts，不覆盖真实存档。当前仓库未提交、无远程推送；保留原有文件与约束。
- 下一工作单元：用户按五步说明试玩，在Phase1内修复反馈；收到明确下一阶段请求后再审查Phase2前置，不自动升级阶段。

## D013完整Phase 1工程就绪（历史，2026-10-09）

- 范围：D013“完整做饭系统＋五类QTE＋像素厨房”；ENGINEERING_READY，PLAYTEST=PENDING，不进入Phase2。Grill实际使用grilling，三项决定D010–D012与范围D013已确认，GRILL_RESULT=RESOLVED。
- 实际可玩：菜单→像素厨房走动/碰撞→近灶E交互；自由投料/份量/批次与四种切型；蓄力/节奏/窗口/维持/顺序五QTE及九工序动作；六属性、四热反应与勾芡/发酵/氧化；双菜、暂停/失焦、回锅、自由摆盘/报废/唯一交付；两组客人独立评分与差评提示；自建方案保存/版本/读取/重做；烹饪侧SAN窗口/TEST_ONLY变体及事件。
- 数据与入口：content/cooking_system.json为v3权威；TDCookingSession复用原公共入口，v3内部委托规则对象；旧v1/v2入口和76项历史验证保留回归。没有万能Autoload、经营或世界系统。
- 全量验证：165/165，1524断言，0失败/跳过，exit0；17套件、41个脚本/场景加载无失败，导入exit0。证据artifacts/check/pre-export-20261009-171533；后续只修了测试自建隔离目录，当前全部文件在干净副本重新通过165/165。
- 干净副本与门槛：artifacts/gate-20261009-171821/gate-proof.json。中文空格路径clean/restored各165/165 exit0；故意失败、必测跳过、解析错误、零测试分别exit1。首次干净副本曾发现测试依赖预存临时目录，现已修复，不隐藏失败历史。
- 图形：真实Compatibility/OpenGL3、NVIDIA RTX3050 Laptop，完整世界/双菜/摆盘/反馈/暂停5张截图，flow=true、exit0；artifacts/full-visual.json与full-*.png。九动作图artifacts/cooking-actions.png另经真实渲染。像素背景和透明角色实际生成并入库。
- 输入：真实Godot键盘事件与Viewport GUI鼠标事件自动联调通过，包括拖动/松手；实际物理键鼠、耳机/扬声器同步NOT_RUN。TDBeatAudio沿用已验证WASAPI占位PCM实现；旧混音证据仅证明后端，不证明新完整流程的物理同步。
- Windows导出：PASS，86项运行资源白名单、独立包启动exit0，artifacts/export/summary.json；build/TownDiner.exe + TownDiner.pck。这是明确的开发演示包，含可选TEST_ONLY试验内容，排除原设计文档/测试/GUT/工具/独立dev入口。远程CI配置完成、NOT_RUN，无远程推送或发布。
- AC：phase-1.md的001–020自动/工程部分PASS；008/009的实物设备体验及整体验收PENDING。具体实现、来源和测试对应关系见覆盖表，未将自动输入当人工试玩。
- 限制：原型UI/程序动作和单张角色配脚步/翻转仍需打磨，不是最终美术；平衡/反应/星级参数PROPOSED。完整SAN成长、旧Tier统一、可选/必经故事、经营/库存/地图均未实现；这些属于后续已划定边界。
- 原始资料：五份SHA256与最初索引一致，artifacts/source-verification.json。未覆盖原资料、未操作真实存档；全部测试读写位于隔离artifacts路径。
- 下一工作单元：用户按README/PLAYTEST试玩并反馈；Phase1内修复体验问题。只有收到明确下一阶段指令才进入Phase2，复用现有机制和接口。

## 旧番茄炒蛋原型检查点（历史）

- 当前阶段：Phase 1 — 番茄炒蛋做菜原型；最新用户范围覆盖旧完整系统 Phase 1 v2。
- 状态：ENGINEERING_READY；工程检查点完成，PLAYTEST=PENDING；不进入Phase2。
- Grill：已读取实际grilling及Godot技能；三题均用户确认，GRILL_RESULT=RESOLVED；自由工序、切型/手艺分离、分层评分见DECISIONS D005–D008。
- 已实现：接单、番茄/鸡蛋/糖/盐、切型、8拍切菜、6秒连续控火、出锅交付、两组需求与独立评分、中文改进反馈、重试/返回/暂停/失焦、每工序属性变化、校准偏移。
- 自动验证：76/76，0失败/跳过，28个脚本/场景加载，exit0；artifacts/check/phase1-final及pre-export-20261009-130221。
- 干净副本：中文空格路径76/76；故意失败/必测跳过/解析错误/零测试均exit1，恢复76/76 exit0；artifacts/gate-20261009-130257/gate-proof.json。
- 图形：真实Compatibility渲染4张原型截图、交付流程exit0；artifacts/phase1-visual.json及phase1-*.png。
- 音频：WASAPI 48000Hz，混音捕获两拍0.301458/0.801458秒，间隔0.5秒；exit0且无泄漏。物理扬声器/耳机/键鼠音画同步NOT_RUN，人工手感PENDING；artifacts/phase1-audio.json。
- 导出：Windows开发演示包、运行资源清单与独立启动PASS；artifacts/export/summary.json。远程CI配置完成、NOT_RUN；没有推送/发布。
- 实现限制：只本菜原型；没有五类QTE、双菜、经营、自建食谱、SAN或正式美术。全部新增平衡数值PROPOSED。音频/输入补偿需实际设备试玩，界面占位。
- 下一工作单元：用户依README五步试玩，确认能依据差评改进下一份菜；反馈仍在Phase1处理。下一阶段必须用户明确指定。

## Phase 0 已验收历史基线（保留）

- 已完成：读取五份设计来源、当时最新版Phase1 v2、总控规范；完成平台与计时两项产品决策。
- 基线：初始仅 `doc/`，无 Godot 工程、AGENTS、阶段记录或 Git 仓库。不重置、不移动原始资料。
- 已实现：主菜单/厨房/返回/重开/暂停；显式装配、版本化契约、配置校验、独立会话、持续输入、时钟/随机注入、设置读写、结构化错误与结果、检查与导出入口。
- 已锁定：Godot 4.7.2.stable.steam.ed1daf0bf、Compatibility、GUT 9.7.1；Windows x86_64同版模板。详情见dependencies.lock.json。
- Grill：`grilling`，实际文件 `C:/Users/Administrator/.codex/skills/grilling/SKILL.md`，无版本字段；已进行两题审查并收到用户答案，GRILL_RESULT = RESOLVED。
- Godot 技能：已读 `C:/Users/Administrator/.codex/skills/godot-gdscript-patterns/SKILL.md` 与 `references/details.md`；使用场景、信号、Resource/运行实例隔离与静态类型模式。协议优先于技能中的全局 Manager 示例。
- 工程验证：PASS，27/27测试，0失败/跳过；20个生产脚本/场景加载通过。五条独立模块套件通过。
- 干净副本/检查门槛：PASS，中文空格路径27/27；故意失败、跳过、解析错误、零测试均退出1；恢复后27/27退出0。
- 图形：PASS（OpenGL3 Compatibility，NVIDIA RTX3050 Laptop，菜单/厨房/暂停3张实际画面）；Windows导出与独立启动PASS，42项运行资源白名单核对通过。
- 设备输入与音频：NOT_RUN（自动输入事件不等于实物设备体验；Phase0无音频功能）；远程CI：配置完成、NOT_RUN；PLAYTEST = PENDING。
- 当时下一步为Phase0试玩；本轮已按用户最新指令进入并完成Phase1工程，上述当前状态优先。
- 版本控制：已初始化本地Git main；未提交、无远程、未推送；没有修改全局Git配置。
- 历史停止点：Phase0当时没有自动进入Phase1，本轮由用户明确请求推进。
