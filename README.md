# GameNameTBD · 小镇食堂

当前入口已更新为 **D033：单店游戏流程与六槽存档**。主菜单为“开始游戏 / 继续游戏 / 载入存档 / 设置 / 退出游戏”，新档从中式食堂门口开始。完整 Phase 4 未完成；本轮验收、失败记录与人工待测见 [game-shell.md](docs/phases/game-shell.md)。

### 当前版本五步试玩

1. 点“开始游戏”直接进最近存档；没有存档时自动新建。另开一档使用“载入存档→新建存档”，选空槽并命名。WASD移动，靠近食堂门口按E进入；餐厅后方门按E到厨房，厨房下方门按E返回。
2. 开店前沿路到菜摊按E买食材，现货立即进入冰箱库存。首轮建议番茄/鸡蛋各4份，油/盐/糖/淀粉/酱油各1份；份量只是试玩备货建议。菜摊显示今日预计客流。
3. 回店与“营业牌”按E交互，勾选当天菜品、调整售价后开门。进入厨房复用既有备菜与QTE：E取放、F开灶、Q取锅料。订单自动排队，按成品匹配交付。营业中不能离店采购。
4. B或餐厅菜谱架打开研习。新档只有蛋炒饭、番茄炒蛋；阳春面和蒸水蛋使用真实厨房操作研习。花灵感买永久资格，80分解锁，失败可免费重试；营业中只能查阅。
5. 营业牌可提前打烊；处理完余单，去“账本”查看日结/保存，去“休息处”进入次日。Esc暂停菜单也可在筹备/日结保存。退出营业会明确提示回退最近边界，不能恢复QTE现场。

存档在 `%APPDATA%/TownDinerPhase0/profiles/slot-01.json` 至 `slot-06.json`：经营、研究、世界和装修写在同一校验包。新档互不继承；在新游戏存档页点“导入旧进度”才会只读导入旧 `shop-v1.json` / `research-v1.json`，源文件保留。坏档/未来版本不会被静默覆盖，可明确恢复已校验备份或临时档。

反引号 **\`** 打开控制台，输入 `debug` 后可用 `help`、`status`、`san 0..100`、`tools`、`debug_off`。旧厨房/营业/员工/分店试验在独立调试入口，不与玩家槽混用。进入旧工具需先打烊并保存。

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

专项检查：`pwsh -File tools/check.ps1 -Suite research`；全量检查：`pwsh -File tools/check.ps1`（单阶段超时预算600秒）；本地导出：`pwsh -File tools/export.ps1`。锁定Godot/GUT版本继续由dependencies.lock.json规定，未升级。图形检查工具：`tools/research_visual_check.gd`，所有验证存档隔离在artifacts/test-storage。

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

正式规范见 `docs/collaboration/README.md`。三条固定工作线是做菜与研发、经济与供货、小镇与事件；每波由其中一人轮值集成，不增加第四人。

```powershell
# 校验三人目录所有权配置
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Validate

# 查看 Phase 4 第 0 波预期分支和现有工作树
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Status -Phase 4 -Wave 0

# 基线提交且工作区干净后，先预演创建四个工作树
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Init -Phase 4 -Wave 0 -BaseRef main -WhatIf

# 角色分支检查自己的未提交文件
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Check -Role cook `
  -BaseRef integration/phase-4-wave-0 -IncludeWorkingTree
```

协作工具兼容 Windows PowerShell 5.1；CI 仍使用 `pwsh`。当前 Phase 4 尚未开工，工作区也有未提交修改，因此现在不要实际运行 `-Action Init`。初始化脚本不会提交、推送或创建 PR。

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

工程与玩家验收分开：最新本地检查证据见docs/PROJECT_STATE.md；真实键鼠/耳机同步、反馈可理解性与好玩程度仍待人工试玩。本阶段交付后停止在Phase2，不自动进入Phase3。
