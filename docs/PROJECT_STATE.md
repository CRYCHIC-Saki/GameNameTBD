# 项目状态

## GitHub 工程同步基线（2026-10-09）

- 用户已明确授权将当前工程上传到 `CRYCHIC-Saki/GameNameTBD`，目标为 `main`，保留远程初始README提交。此次仅同步工程，不创建正式发行版、不推进Phase2。
- 上传前检查：`tools/check.ps1 -ReportName github-prepush-20261009`，锁定版引擎导入/加载/测试均exit0，205/205通过，0失败/跳过；本地证据在 `artifacts/check/github-prepush-20261009/`。
- Git保留源码、素材、测试依赖、版本锁及设计资料；缓存、工具下载、检查产物和导出包不入库。六份 `doc/source/` 原文在Git暂存区与工作文件逐字节相同，已单独禁用换行转换。
- 远程CI由推送触发，实际结果以 [GitHub Actions](https://github.com/CRYCHIC-Saki/GameNameTBD/actions) 对应提交为准；下面各阶段的NOT_RUN/未推送为当时历史状态。人工试玩仍为PENDING。

## 当前检查点：Phase 1 自动工序与界面纠正（D015，2026-10-09）

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
