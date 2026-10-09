# 小镇食堂开发入口

- 每阶段先读 `docs/DEVELOPMENT_PROTOCOL.md`、`docs/PROJECT_STATE.md`、`docs/DECISIONS.md`、对应阶段报告和用户最新范围。原始资料在 `doc/source/`，只读。
- 当前仅执行 Phase 1。最新用户纠正以 `doc/source/做菜操作.md` §3–7 与 DECISIONS D015 为准：台面功能位，实际取料→菜板自动备菜→搬入锅并加鸡蛋→E自动烹饪→端盘出餐；复用已有模型，不重建、不推进Phase2。
- 七模块复用五类QTE；炒菜按M2→M3下油/下料→M3∥M4→M6→M3勾芡→M7自动推进，蒸菜/M5炖煮与双锅按外置逐拍表运行。玩家不能选择下一工序。移除文档外的份量/刀数菜单、返工、拖盘、自建方案、测试开关和旧原型菜单；这些旧规则只保留兼容测试，不能当作生产功能重新暴露。
- 阶段入口实际使用 `grilling`（用户认可等价 Grill Me），通常最多询问 0–3 个阻塞产品问题；已答问题不重复询问，不再请求开始确认。
- Godot 开发必须使用 `godot-gdscript-patterns`。按任务使用表格、visualize、imagegen、skill-creator，不能将安装等同调用。
- Windows 单机 2D、键鼠；QTE 中游戏时间正常流逝，主动暂停冻结游戏与操作时钟。引擎/依赖按 `dependencies.lock.json`，禁止自行升级。
- 小型模块化单体、静态类型 GDScript；组合入口装配依赖，不建万能 Autoload。遵守 `docs/ARCHITECTURE.md` 与 `docs/CONTRACTS.md`。
- 模板只读、会话独立，界面只发送意图；菜品计算与评分分离。原始 towns.json 不属于运行时配置。
- 改共享契约先更新契约与验收；共享文件负责人、分工边界见 `docs/COLLABORATION.md`。
- 使用 `tools/check.ps1` 的真实结果；零测试、跳过、解析错误或超时不能算通过。人工试玩未执行记 PENDING。
- 不覆盖用户改动，不操作真实玩家存档，不擅自推送发布或修改全局环境。记录准确断点并在本阶段交付后停止。
