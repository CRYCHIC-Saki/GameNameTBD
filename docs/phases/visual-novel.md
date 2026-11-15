# D072/R1 原生 VN 插件开篇（2026-11-13，ENGINEERING_READY / PLAYTEST_PENDING）

## D072-R1：真正使用插件（2026-11-13）

本节覆盖下方 D072 的“组件组合”契约；旧验证只作历史，不视为原生运行验证。用户明确要求直接使用插件。实际读取 grilling（C:/Users/Administrator/.codex/skills/grilling/SKILL.md，无版本字段）与 godot-gdscript-patterns；vn_runtime_facts按技能要求只读调查。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：范围仍为框架和开篇，用户已确认插件，既有CG/保存/昵称/任务规则充分明确。

实际链路：启用 project.godot 编辑器插件 → VNEngineMain → 本地继承完整VNEngineStageScreen → VNEngineStoryRunner/CommandBus → VNEngineDialogUI/背景/角色系统。原生剧本位于 content/story/vn/scenario/intro/script.txt，配置/原图Atlas在同目录。三段电影依旧是真实AnimationPlayer；td_cg、td_name分别为阻塞节点。插件自身实现逐字、自动、快进与回看；游戏仅提供中文样式、暂停、CG/昵称与进度交接。

| AC | 来源、输入 | 可观察结果/验证 |
| --- | --- | --- |
| AC-PHASE-4-VN-R1-001 | 用户要求；正式新档 | 真实Main/Runner/DialogUI及原生TXT加载，台词逐句对照原JSON，完成交还港口 |
| AC-PHASE-4-VN-R1-002 | D054/命名门槛；自动/重复输入 | 三段14/6/10秒交错，画外音不露阿铃；CG与昵称不可被自动、快进、双击或旧回调越过；只命名/完成一次 |
| AC-PHASE-4-VN-R1-003 | D059；普通退出/回看/取消 | 独立插件存读拒绝、无目录写入；暂停字速冻结，取消立即清单例，模板昵称隔离；普通对话恢复按钮 |
| AC-PHASE-4-VN-R1-004 | 可运行交付 | 同一检查入口导入/加载/原生及旧教学回归；烘焙TXT.RES与Atlas实际进包；图形输入/导出证据单列 |

没有测试替身代替插件。原始资料、D071现有改动和真实存档保持。补丁详见 addons/vn_engine/TOWN_DINER_INTEGRATION.md；上游版本不升级。证据目录 artifacts/vn-runtime-20261113。初轮语法错误、旧测试仍驱动TDDialogue、重复昵称提交、延后启动取消及四个未收集资源请求的失败日志保留，修复后另验。

使用：Godot打开 dev/vn_opening_test.tscn 按F6安全预览；正式游戏新档也走同一流程。点击台词推进，右下自动/快进/回看，右上暂停；CG可跳过当前片段，昵称必填。命名和任务进度仍按游戏原保存规则处理。

最终统一检查 artifacts/check/pre-export-20261113-144413：4脚本、30/30独立用例、611断言，无跳过，导入/加载/测试均退出0；加载155资源。包含真实Main/Runner/UI、CG/命名阻塞、取消后重入、自动/回看/暂停、内存存档拒绝磁盘写入、正式新档昵称任务交接和旧厨房教学。
最终导出 tools/export.ps1 -CheckSuite visual-novel 退出0：1130运行资源，原生script.txt.res、配置及Atlas逐项检查；真实EXE无图形启动3轮各4项、菜单/存档94项PASS。本地build/TownDiner.exe/.pck于2026-11-13 14:45更新。
最终真实EXE Compatibility图形：artifacts/vn-runtime-20261113/exe-gpu-paired.log，21检查/6截图、退出0，无解析/运行错误或对象残留。一次性配对EXE/PCK来自同一导出runtime.zip，只替换隔离验证入口，生产资源不变；涵盖真实鼠标、自动命名阻塞、实际Profile任务与港口控制交还。截图在 artifacts/export/novel-probe/screenshots。源码早期图形21项也通过，其退出残留已修复并在最终EXE复验。
模板禁止 --main-pack 路径覆盖（本轮首次尝试退出1且记录），故用相同EXE配同名PCK验证成功；此前D072两次图形超时不抹除。本轮正式图形验证已完成，真人观感与连续设备试听仍PENDING；全仓/远程CI未运行。
43保护资料SHA256逐项一致，原DOCX/定妆不动。未提交推送，root写入锁释放。AC-R1-001–004工程项PASS，停在本轮试玩点。

## D072 初次组件预览历史（以下实现边界已被R1覆盖）


范围：用户授权搭建 Visual Novel Engine 框架并先修改开篇。既有三段动画及九拍原文顺序不变，港口对白改用独立背景与半身立绘；其余章节、普通交谈、钱物/任务/存档规则不变。

Grill：实际读取 `C:/Users/Administrator/.codex/skills/grilling/SKILL.md`（无版本字段）及 `godot-gdscript-patterns/SKILL.md`。只读调查由 vn_story_facts 执行，root唯一写入。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：既有D053/D054明确演出仍为动画，D059明确保存权威；本轮仅呈现迁移，无新玩法决定。

## 契约与实现边界

- 原文权威为只读DOCX/TXT及已审核 `content/story/opening.json`。当前DOCX有用户未提交修改，本轮不重新导入或覆盖。
- 锁定上游 `kaanakgundogdu/godot-vn-engine` 0.23.0，commit `a2231b2dd985e0ca045f88b9cea993e1eb58a0c6`。使用其真实背景/角色呈现组件，TDVisualNovelStage适配已有TDDialogue。此轮不启用插件独立主菜单、StoryRunner/全局存档、回滚和设置，不冒称全部剧本已迁入其脚本语言。
- TDDialogue仍唯一拥有对白拍序、昵称门槛、CG秒表和取消结果；View只呈现，StoryGuide只在原closed回调提交任务。背景/角色为短生命周期表现对象，无user://写入。
- 可扩展的场景配置区分背景ID、已登场角色、说话者和表情。进入/结束/重复进入清空呈现状态，失焦和暂停冻结表现动画。
- Shared owner=root：addons/vn_engine、src/story/vn_stage.gd、src/ui/dialogue_view.gd、dependencies.lock.json、相关测试/工具/导出/记录。其余未提交成果保持；不推送。

## 验收

| ID | 来源与条件 | 结果与检查 |
| --- | --- | --- |
| AC-PHASE-4-VN-001 | 用户本轮/实际插件 | 锁定版本；真实插件角色/背景实例接入正式入口，导入加载通过 |
| AC-PHASE-4-VN-002 | 开篇9拍 | 14/6/10秒动画交错原台词；独立港口背景与双立绘；画外音不提前暴露阿铃 |
| AC-PHASE-4-VN-003 | 既有命名/任务 | 昵称必填，结束只推进一次；取消/回看不领奖或推进；交还港口控制 |
| AC-PHASE-4-VN-004 | D059/暂停 | 世界时钟冻结，无插件独立存档；失焦/暂停/重入无残留 |
| AC-PHASE-4-VN-005 | 可运行交付 | 真实GPU截图、导出资源检查与本地包启动；人工观感单独PENDING |

## 实际验证与交付

- 统一入口：`pwsh -NoProfile -File tools/check.ps1 -Suite visual-novel`。本机为避免修改Steam编辑器设置，复制同SHA256的锁定引擎到 `artifacts/vn-framework-20261113/engine/godot.exe`，加项目内自包含标记，并通过 `-GodotPath` 使用；模板亦从锁定目录复制。引擎版本和渲染器未升级。
- 最终统一检查 `artifacts/check/pre-export-20261113-132659`：4脚本、26/26用例、595断言，导入/加载/测试退出码均0，无跳过。覆盖原九拍、画外音、真实同槽命名/任务交接、教学赠料回归、暂停、取消、重复进入和长按不能跨过命名。
- 最后新增独立预览场景后，再次导入及加载检查：152资源、0失败，见本轮 `final-import.log` / `final-load.log`。
- 源工程Compatibility图形检查：18项、6图，实际鼠标点击，见 `gpu-final.log`。最终导出PCK用同版本编辑器执行一次性入口：18项、6图、退出0，见 `pck-gpu-console.log`；这证明打包资源完整，不等同于导出EXE图形验收。
- `tools/export.ps1 -CheckSuite visual-novel` 退出0，1111项运行资源检查、真实EXE无图形启动退出3轮各4项、实际EXE无图形界面/存档探针94项PASS。`build/TownDiner.exe/.pck` 2026-11-13 13:28更新。插件示例、编辑器工具、开发入口不进正式包；未启用独立插件保存。
- **尚未通过**：导出EXE直接脚本和一次性PCK两种自动图形探针均90秒超时（未报告PASS，过程只终止本轮创建的进程）。同一PCK用锁定编辑器运行通过，尚不能判定模板/图形环境与探针启动差异的原因。不能宣称EXE完整图形验证完成。初次证书/编辑器权限错误、初次一项测试缺少末句关闭点击的失败日志均保留。
- 43份原资料/角色保护文件SHA256一致。已有D071未提交改动保留，原DOCX不写入，真实存档未修改。所有权检查469路径PASS；未提交/推送。全仓测试、远程CI未运行；人类观感、连续设备试听PENDING。

AC结果：001–004 PASS；005的源工程与导出资源包图形检查PASS、EXE无图形检查PASS、EXE图形UNVERIFIED。没有使用假剧情/假奖励测试替身；插件呈现组件是真实实例，业务进度仍由原游戏管理。

## 查看本轮样例

1. Godot打开 `dev/vn_opening_test.tscn` 后F6，独立反复预览，不创建经营存档；或正常F5在空槽开始新游戏。
2. 观看三段动画与穿插对白，确认海港背景、大立绘和明暗关系；阿铃画外音时不显示她。
3. 输入名字，走完开篇；正式入口恢复港口地图与护送任务，独立入口提供再次预览。
4. 暂停/切出窗口再恢复，确认不跳句；本轮先评估呈现，其他章节维持原样。

下一步为本轮画面反馈及导出EXE图形检查缺口，不自动迁移后续剧情。


## 2026-11-15 远端美术兼容整合
原生Main/Stage/StoryRunner/DialogUI继续拥有开篇；远端背景与四张对应表情由content/story/vn/backgrounds和portraits只读引用，资源清单同时保留两侧新增文件。非开篇羊皮纸对话仍走原TDDialogue，修复旧纯色StyleBoxFlat强转；插件按钮与姓名文字在宿主层用深色墨水适配，不改上游插件文件、剧情段落或Profile9保存规则。最终sync-art117用例/8057断言（含本模块）及原生图形21项/6图通过，源码验证，不是新EXE或远程CI验收。详见PROJECT_STATE和artifacts/sync-20261115-art；原D072-R1失败日志与本次首轮面板错误/中断都保留。
