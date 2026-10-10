# GameNameTBD · 小镇食堂

当前检查点：Phase 2 单店连续营业工程版。工程仓库：[GitHub](https://github.com/CRYCHIC-Saki/GameNameTBD)。远程CI实际结果以对应提交的 GitHub Actions 为准。

已打通采购备货 → 菜单定价 → 自动来客 → 真实取料/备菜/烹饪/端盘 → 评价和日结 → 次日 → 保存继续。首批5道菜：番茄炒蛋、干炒牛河、麻婆豆腐、宫保鸡丁、辣椒炒肉。复用D015/D016像素厨房、五类QTE与菜谱打谱；没有重建做菜系统。新增数值为PROPOSED，画面和音轨仍为原型，人工玩法验收待完成。

## 五步试玩

本地双击 `build/TownDiner.exe`，保留同目录 `TownDiner.pck`。仓库不包含导出包；克隆后用下方启动/导出命令。

1. 选“新开一间店”，先只上架番茄炒蛋，保留参考价。点“补齐”，再点三次“再备1份”，为第一天准备四份；点“开门营业”。
2. 客人到来后在右侧点“左锅备菜”。WASD/方向键走到食材架，E打开取料：拿番茄，到砧板E开始按谱备菜，完成后砧板E取走、左灶E放入；再从料架拿鸡蛋放入同一锅。
3. 空手对灶台E自动做菜。按显示的方向键/空格、鼠标火候条及调料柜完成每段；M6不用同时控温。出锅先看预告，出现提示后按住空格约2秒，到绿区松开。Esc暂停，失焦自动暂停。
4. 灶台E端菜，右下出餐台E交付，读客人的主要扣分原因。选择下一单继续；缺料可售罄/取消，或提前打烊。另一口锅可独立接单，手上和菜板仍各只能放一份食材。
5. 日结核对收支/库存和反馈，可命名保存这份做法。点“准备下一天”，调整上架菜、备货和售价，自建菜也可上架。重复经营3天，再保存并从主菜单“继续经营”检查日期与库存。

营业默认6分钟、顾客耐心4分钟，到点停止接客后处理余单。看账本/料架弹窗不会停营业；主动暂停才冻结。预留不是消耗：拿主料或提交调料时扣实际用量，未用调料释放回可用库存；取消/超时退预付款、已用料损失。应急补助只在次日起筹备阶段确实买不起最便宜补货时可领取，每天一次。

自建菜保存食材与完整自动工序方案，不保存分数；改名保留ID，下次仍需真实按谱。未完成备菜、缺调味等方案会说明原因并拒绝保存。当前支持基于已审核五菜的完整方案，不含自由工序编辑器。

## 保存与恢复

仅筹备和日结能保存；开门前自动保存筹备，准备下一天前保存日结。营业中退出会回到最近边界，不能恢复顾客队列或QTE；返回和关闭窗口都会提示。筹备或日结的后续修改请点“保存进度”。

当前Windows存档：`%APPDATA%/TownDinerPhase0/shop-v1.json`，保留既有用户目录。写入有校验、临时文件和上一份有效备份；坏档不静默覆盖，继续页面可明确选择恢复已校验备份/临时文件。未知版本不降级覆盖。新开店首次保存前会确认并保留旧档。测试只使用 `artifacts/test-storage`。

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
- `docs/phases/phase-2.md` / `docs/systems/business.md`：单店营业验收、内容来源、规则与建议值。
- `docs/ROADMAP.md`：当前检查点与后续里程碑。
- `docs/SOURCES.md`：原始资料索引与指纹。原始文件保留在 `doc/source/`。

工程与玩家验收分开：最新本地检查证据见docs/PROJECT_STATE.md；真实键鼠/耳机同步、反馈可理解性与好玩程度仍待人工试玩。本阶段交付后停止在Phase2，不自动进入Phase3。
