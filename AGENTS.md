# 小镇食堂开发入口

- 每阶段先读 `docs/DEVELOPMENT_PROTOCOL.md`、`docs/PROJECT_STATE.md`、`docs/DECISIONS.md`、`docs/FULL_IMPLEMENTATION_FLOW.md`、`docs/AI_FILLED_DETAILS.md`、对应阶段报告和用户最新范围。原始资料在 `doc/source/`，只读。
- 产品规则按 1013 会议→《美食游戏设计大纲 v0.2》→带编号的 `【AI填充细节 AI-xxx】` 解释。AI 填充不能冒充用户决定；覆盖时保留编号和历史。
- D030（2026-10-21）仅授权菜谱研习切片，见 `docs/phases/recipe-study.md`；不等于整个 Phase 4 完成。新进度只有蛋炒饭C01、番茄炒蛋C02；历史合法解锁保留。HTML前置为ALL，灵感买永久资格，完成谱面>=80解锁；其他菜系只能由剧情推荐接口开放。生产入口不再用旧60分/Perfect直接解锁；未配谱面不扣灵感。独立research-v1.json不回写营业账。
- Phase 3 已于 2026-10-13 由小组确认为开发完成，范围见 D021–D026 与 docs/phases/phase-3.md、phase-4.md。下一阶段是 D028 版 Phase 4，执行 `doc/agent_prompts/Phase_4.md` 与 `docs/phases/plan-1013.md`；未另获开工授权前不改玩法。Phase 2 的厨房、订单和日结保持可用，不把新世界账写入旧营业档。
- 七模块复用五类QTE；炒菜按M2→M3下油/下料→M3∥M4→M6→M3勾芡→M7自动推进，蒸菜/M5炖煮与双锅按外置逐拍表运行。玩家不能选择下一工序。移除文档外的份量/刀数菜单、返工、拖盘、自建方案、测试开关和旧原型菜单；这些旧规则只保留兼容测试，不能当作生产功能重新暴露。
- D016最新修正：切菜落刀与转向都按菜谱打谱；调味独占鼠标，不与手动控温抢输入；QTE须显示真实逐拍反馈，预告/起手/长按分开计时。当前入口和字段见CONTRACTS的D016部分。
- D020优先：玩家选切型后按谱，备菜不依赖订单；E取放、F开灶台、Q取锅料。非空锅按材料+炒/蒸识别已知或锁定菜，未知组合完整流程后失败。原料/切配品可冷藏返还且保留状态，开始加工后只能整锅继续或丢弃。五菜初始解锁、汽锅鸡全计分工序Perfect且必需项齐全可提前解锁。失败菜误送匹配全队首客，幂等负评。见DECISIONS/CONTRACTS D020。
- D019历史营业交互（切型选择已被D020覆盖）：单一冰箱自由拿料、自动只读订单；同主料/工序按同一种菜匹配，最早同菜顾客决定谱面，不弹选谱菜单。切型要求改变切菜密度，口味要求改变长按调料量。模型提交前原子扣实际库存；搬运不重复扣料。缺料订单自动谢客并小幅扣人气；超时保留实体食物，交付匹配最早同菜并收款。见DECISIONS/CONTRACTS D019。
- Phase2允许经营界面中的最简自建方案保存/命名/上架，覆盖Phase1移除配方库的范围限制；不恢复自由工序菜单。限时自动来客、售罄/取消/提前打烊及条件式应急补助；仅筹备/日结边界保存。
- 阶段入口实际使用 `grilling`（用户认可等价 Grill Me），通常最多询问 0–3 个阻塞产品问题；已答问题不重复询问，不再请求开始确认。
- Godot 开发必须使用 `godot-gdscript-patterns`。按任务使用表格、visualize、imagegen、skill-creator，不能将安装等同调用。
- Windows 单机 2D、键鼠；QTE 中游戏时间正常流逝，主动暂停冻结游戏与操作时钟。引擎/依赖按 `dependencies.lock.json`，禁止自行升级。
- 小型模块化单体、静态类型 GDScript；组合入口装配依赖，不建万能 Autoload。遵守 `docs/ARCHITECTURE.md` 与 `docs/CONTRACTS.md`。
- 模板只读、会话独立，界面只发送意图；菜品计算与评分分离。原始 towns.json 不属于运行时配置。
- 改共享契约先更新契约与验收；三人并行规范见 `docs/collaboration/README.md`，机器所有权见 `collaboration.config.json`，当前锁见 `docs/collaboration/CURRENT_WAVE.md`。角色分支先运行 `tools/collab.ps1 -Action Check`；共享文件只由轮值集成者在集成分支修改。
- 使用 `tools/check.ps1` 的真实结果；零测试、跳过、解析错误或超时不能算通过。人工试玩未执行记 PENDING。
- 不覆盖用户改动，不操作真实玩家存档，不擅自推送发布或修改全局环境。记录准确断点并在本阶段交付后停止。

- D031覆盖旧研习四轨：研习复用真实FullKitchen/Lane/BeatSheet/GuidedCookingView；B打开暂停覆盖层、返回原场景，营业仅查阅；锁菜系不可浏览。边框选择不代表掌握，历史解锁保留。当前验收见docs/phases/recipe-study.md最新修正。

- D032（2026-10-22）覆盖研习时间/选择边行为：暂取消每日研习时间额度与新耗时；失败结果立即免费重试，旧时间用尽也可开始；营业仅查阅不变。选中金线展示直接前置，掌握绿线独立，真实解锁条件不变。见recipe-study R11–R12及AI-039。
