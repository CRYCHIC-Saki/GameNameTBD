# GameNameTBD · 小镇食堂

当前检查点：Phase 1 完整烹饪厨房。工程仓库：<https://github.com/CRYCHIC-Saki/GameNameTBD>。

当前版本按 `doc/source/做菜操作.md` §3–7 和用户最新纠正D016运行：台面取料→砧板按菜谱打谱→搬入锅→自动烹饪→端盘出餐。七模块复用五类QTE；支持逐拍表、键盘翻炒与鼠标控温并行、后台炖煮和双锅。顺序调味独占鼠标，命中反馈常驻短时显示；主菜单只有进入/退出。新增数值是PROPOSED，美术/音轨仍是原型；没有经营或库存经济。

## 直接体验

本地已导出时，双击 `build/TownDiner.exe`，并保留旁边的 `TownDiner.pck`。这是开发演示包，不是正式发行版。Git仓库不包含导出包；首次克隆后按下方“工程运行”安装锁定版本并启动，或执行 `tools/export.ps1` 生成本地试玩包。

1. 选“走进厨房”，WASD/方向键走到左上番茄箱，E拿取；到右上标着“砧板”的台面按E放下，备菜自动开始。
2. 按菜谱给出的“空格落刀→D右转→空格落刀”在环收拢时依次按键；全命中切成块，转向不算刀数。结束自动回厨房，砧板E取走、左灶E放入，再拿鸡蛋放入同一锅。
3. 空手对左灶按E，自动依次呈现：点火→下油/下料→翻炒与控温并行→顺序调味→勾芡→出锅。按画面方向键/空格、拖靠鼠标控温、点击材料柜；不选下一工序。
4. 出锅先看2秒预告，出现“现在按住空格”后按住约2秒，到绿区中心松开。起手等待与蓄力分开；结束回厨房后在灶台E端起成品，到右下方出餐台E提交。
5. 看两位客人的评价，E回厨房，再取料做下一份。Esc暂停，失焦自动暂停。双锅、番茄蒸蛋、炖牛肉复现见docs/PLAYTEST.md。

每个工序结束自动接下一个；没有输入也会按实际Miss结束，不会给假成功或卡死。E返回厨房时操作/冷却继续，主动暂停或失焦才冻结。M5炖煮条在厨房和切菜等界面都常驻。蒸笼共用右锅槽，不能作为第三口锅同时工作。番茄蒸蛋/炖牛肉及新增柜内材料数值属于TEST_ONLY开发样例，不是正式内容和平衡验收。

玩家入口已移除旧工序菜单、刀数/份量选择、拖盘、返工、自建配方和辅助开关；底层历史规则保留回归。输入/音频偏移接口仍保留供设备验证，当前玩家流程使用默认值；真实键鼠和听觉同步需人工测试。

每拍以绿色Perfect、黄色Good或红色Miss反馈，并说明早晚、错键或漏拍。键盘和调味目标通常间隔1秒，主要工序预告2秒；原时间窗50/100ms保留。M6开始前结束本锅M4；双锅调味期间另一锅火候显示托管，保持当前位置并暂时排除控温判分，游戏时间照常推进。上述时长均为可调初值。

## 工程运行

已锁定 Godot 4.7.2 stable、静态类型 GDScript、Compatibility、GUT 9.7.1。当前机器 Godot 在 Steam 安装目录，未修改全局环境；准确路径、版本与校验值见 `dependencies.lock.json`。命令需要 PowerShell 7.2+，本机实测7.6.5。

在项目目录运行：

```powershell
pwsh -NoProfile -File tools/run.ps1
pwsh -NoProfile -File tools/run.ps1 -FullKitchen
pwsh -NoProfile -File tools/run.ps1 -Cooking
pwsh -NoProfile -File tools/run.ps1 -Module
pwsh -NoProfile -File tools/check.ps1
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

`export.ps1` 先执行同一检查入口，再导出Windows包、核验资源白名单并执行无界面启动。导出不含GUT、测试、原始设计资料、独立模块入口和工具脚本；本包明确为开发演示，旧兼容依赖尚随代码打包但不从菜单暴露。

CI配置在 `.github/workflows/check.yml`，推送和Pull Request调用同一 `tools/check.ps1`。每次提交的远程结果及日志见 [GitHub Actions](https://github.com/CRYCHIC-Saki/GameNameTBD/actions)，本地通过不代替远程通过。

## 文档入口

- `AGENTS.md` / `docs/DEVELOPMENT_PROTOCOL.md`：总控规范，之后每阶段必读。
- `docs/PROJECT_STATE.md` / `docs/DECISIONS.md`：当前状态、已确认决定、建议与冲突。
- `docs/ARCHITECTURE.md` / `docs/CONTRACTS.md`：模块职责、状态所有权和公共接口。
- `docs/COLLABORATION.md`：目录归属、共享文件负责人、独立检查与接口变更。
- `docs/phases/phase-0.md`：AC与实际验收证据。
- `docs/phases/phase-1.md`：完整系统AC与实际证据；旧76项验收保留历史。
- `docs/systems/cooking.md`：当前v3接口、建议参数、数据扩展与外部接入；PHASE1_INTERFACES.md为旧v2原型。
- `docs/ROADMAP.md`：Phase1–2可执行任务与后续里程碑。
- `docs/SOURCES.md`：原始资料索引与指纹。原始文件保留在 `doc/source/`。

工程与玩家验收分开：最新本地检查证据见docs/PROJECT_STATE.md；真实键鼠/耳机同步、反馈可理解性与好玩程度仍待人工试玩。本阶段交付后停止，不自动进入Phase2。
