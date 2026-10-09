# Phase 0 验收与执行记录

状态：ENGINEERING_READY / PLAYTEST=PENDING。范围：以2026-10-09用户“项目基本框架与协作基线”补充为准。工程与自动验收完成；不会自动执行Phase1。

## 验收标准（实现前建立）

| AC | 来源、输入与可观察结果 | 验证方式 / 初始状态 |
|---|---|---|
| AC-PHASE-0-001 | 应用结构：主菜单进入厨房、返回、重复进入，当前场景只有一个，无重复结果 | PASS：test_application重复5次+释放验证 |
| AC-PHASE-0-002 | 配置：有效DEV_ONLY样例可加载；缺字段、未知版本、重复ID、坏枚举/范围/引用必须定位错误 | PASS：test_content 4项，包含嵌套Object/非有限值拒绝 |
| AC-PHASE-0-003 | 独立实例：同模板建两会话，修改嵌套运行状态/快照不污染另一会话或模板 | PASS：test_session实例/快照与test_content嵌套Resource隔离 |
| AC-PHASE-0-004 | 通路：配置→会话→请求→InputMap事件→连续控制→状态→结构化结果→重开 | PASS：真实场景+Input.parse_input_event；物理键鼠设备NOT_RUN |
| AC-PHASE-0-005 | 非法请求无副作用；重复完成、取消后的旧帧、新会话收到旧输入拒绝且原因明确 | PASS：test_session 6项；test_time_qte旧输入；应用旧场景清理 |
| AC-PHASE-0-006 | D004：实时独立、游戏/QTE同步推进；主动暂停冻结规则、输入不可穿透；恢复需新按下 | PASS：单元+Esc事件+失焦+重复键 |
| AC-PHASE-0-007 | 随机源和时间可注入；同种子同结果、会话彼此独立、视觉不消耗业务随机 | PASS：test_time_qte 7项含分片等价、超时边界 |
| AC-PHASE-0-008 | 设置写读真实往返；坏JSON、未知版本和写入失败有错误且保留原文件；只用隔离测试目录 | PASS：test_storage_scoring设置3项，路径在artifacts |
| AC-PHASE-0-009 | 检查入口覆盖导入/脚本与场景加载/契约/单元/集成，输出数量、日志与退出码 | PASS：发现27/执行27/通过27/失败0/跳过0；四阶段退出0 |
| AC-PHASE-0-010 | 隔离故意失败、零测试、解析错误被检查链拒绝，原工程不受影响，正常检查恢复 | PASS：另含必测pending拒绝；退出码0/1/1/1/1/0 |
| AC-PHASE-0-011 | 引擎与依赖锁定；干净中文空格路径副本能检查；本地Windows导出与启动可验证 | PASS：净副本27项，导出/白名单/独立启动均退出0 |
| AC-PHASE-0-012 | 模块职责、公共契约、分工共享文件负责人、Phase1–2可执行任务明确 | PASS：文档自审，content4/cooking6/qte7/platform4/integration6独立通过 |

AC中的工程部分全部通过，失败0。人工设备/手感与音频未验证，不混入工程通过结论。

## 执行记录

- 初始事实：仅资料，未发现Git、AGENTS、project.godot或既有测试。原资料不移动。
- 已实际读取grilling技能并提出平台/计时两题，用户已回答，GRILL_RESULT=RESOLVED；没有剩余阻塞产品问题。
- 实现前列出上述AC；先建立关键失败/边界测试，再实现对应模块。

## 实际执行证据

| 检查 | 命令 / 结果 / 证据 |
|---|---|
| 全量最终回归 | `pwsh -NoProfile -File tools/check.ps1`；27/27、exit0；artifacts/check/pre-export-20261009-121846/summary.json与JUnit |
| 生产加载 | 同一入口load阶段；20个脚本/场景、0失败、exit0；对应load.console.log |
| 独立工作线 | `tools/check.ps1 -Suite content/cooking/qte/platform/integration`分别执行；4/6/7/4/6测试，各exit0；artifacts/check/module-*/summary.json |
| 干净路径及失败门槛 | `pwsh -NoProfile -File tools/verify_gate.ps1`；中文空格副本27/27；故意失败/跳过/解析/零测试退出1，恢复27/27退出0；artifacts/gate-20261009-122044/gate-proof.json |
| 图形渲染 | Godot `--path F:/MyGameTBD --script res://tools/visual_check.gd --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy`；exit0，3图；artifacts/visual.log、menu.png/kitchen.png/paused.png |
| Windows包 | `pwsh -NoProfile -File tools/export.ps1`；export/资源清单/独立启动exit0；42项运行文件；artifacts/export/summary.json及runtime-manifest.json |
| 原资料 | 五份来源SHA256与初始一致；docs/SOURCES.md |
| 远程CI | .github/workflows/check.yml已配置，共用check.ps1；官方4.7.2校验清单地址已核实；远程NOT_RUN |

环境：Godot 4.7.2.stable.steam.ed1daf0bf，Windows导出模板4.7.2.stable.official.ed1daf0bf，GUT9.7.1，PowerShell7.6.5；OpenGL3.3 NVIDIA 581.83 / RTX3050 Laptop。

首次运行实际暴露并修复：Input.parse_input_event缓冲未刷新导致2项集成失败；测试刷新后通过。GUT布尔命令行值导致JUnit文件追加时间戳，移除多余参数改用明确默认。导出包初次启动传入--path造成exit1，按相邻PCK查找方式修正，正式导出脚本现已独立验证。失败日志保留，不计为最终通过。

## 已实现 / 测试替身 / 后续玩法

- 已真实实现：主入口与菜单、开发厨房模块入口、进出重开与销毁、暂停/失焦、InputMap连续输入、显式依赖装配、可注入时间/随机、配置加载校验及active清单、模板/实例/快照隔离、操作请求与结果去重、设置读写错误处理、日志、检查门槛、导出及协作契约。
- 仅测试替身：test_time_qte.gd中的FixedRandom，只验证注入边界。真实场景用正式目录/会话/随机/时钟/输入，未用mock代替引擎集成。
- 开发样例：hold_probe是明确DEV_ONLY的持续输入最小规则，不是五类正式QTE之一已完成的承诺；work_units不是菜品品质。
- 独立评分边界：实际被厨房调用但返回NOT_IMPLEMENTED，无满意度/星级。不是“已实现评分”。
- Phase1负责：六项菜品属性、自由工序/反应、五类QTE、双菜并发、二次加工、自由摆盘、自建菜谱、烹饪侧SAN、独立评分和正式首菜。

## 人工验收与尚存限制

- PLAYTEST=PENDING：真实键盘、鼠标、交互舒适度、长时间操作、音频/输入延迟未体验；音频未实现，图形截图不冒充手感验收。
- 界面系统字体依赖Windows可用中文字体，已在当前目标机器渲染确认；其他Windows设备未验收。
- Steam可能自动更新引擎；检查入口以锁定版本/hash拒绝漂移。其他平台不在当前验收范围。
- 设置存储只是最小设置往返和错误保护，未承诺断电原子恢复、经营存档或任意QTE恢复。
- 本地Git已初始化，但尚未提交/推送，无远程仓库；远程CI未运行。

试玩步骤见README（5步）。下一步为Phase0人工试玩反馈；收到用户Phase1请求后可复用工程进入Phase1 v2，先解决该阶段真正阻塞规则。此处停止，不自动推进。
