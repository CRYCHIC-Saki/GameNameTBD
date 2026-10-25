# D037 库存与熟练制作

来源：2026-10-25用户六项反馈及两项Grill答复；历史对照D019/D020、1013会议、AI-002/003。实际读取并执行[C:/Users/Administrator/.codex/skills/grilling/SKILL.md](C:/Users/Administrator/.codex/skills/grilling/SKILL.md)和[godot-gdscript-patterns/SKILL.md](C:/Users/Administrator/.codex/skills/godot-gdscript-patterns/SKILL.md)，无版本字段。GRILL_RESULT=RESOLVED：仅已解锁主料＋全部调料；合格制作分累计400。仅当前增量，不扩展其他Phase4玩法。

## 验收标准

| AC | 输入/条件 | 可观察结果 | 验证 |
|---|---|---|---|
| AC-PHASE-4-037-001 | 新档两道中餐/解锁新增菜 | 市场、工厂仅可买对应主料，所有调料可买；伪造请求拒绝，历史已持有材料保留 | 规则+真实入口 |
| AC-PHASE-4-037-002 | 同食材不同入库日、跨日、旧档 | FEFO扣除，到期损耗与库存一致；保存重载一致；退回切配品不改期 | 单元/迁移/集成 |
| AC-PHASE-4-037-003 | 购瓶/袋、长按不足/耗尽、双锅和取消 | 按实际时长消耗且不负数/不双扣，风味按实量；耗尽提醒、灰图标不能点 | 单元+真实QTE |
| AC-PHASE-4-037-004 | 空/有库存、已切品 | 冰箱仅显示持有品，工厂同四类，图标/数量/最早到期可读 | 场景/GPU |
| AC-PHASE-4-037-005 | 边界时间、部分Good/Miss、轻微偏味 | 宽松参数生效；个别失误不把整工序清零；未声明要求仍不扣分；极端/缺项仍有后果 | QTE/评分回归 |
| AC-PHASE-4-037-006 | 79.99/80、399/400、重复成品、研习/自动 | 仅合格手工按实际制作分累计，>=400开放，跨槽/存档隔离且幂等 | 单元/存档 |
| AC-PHASE-4-037-007 | 熟练菜手动/自动、两锅、缺料、暂停、取消 | 同一固定工序真实消耗时间/原料/调料，产出可交付，自动不刷熟练；暂停冻结无残留 | 真实厨房集成 |
| AC-PHASE-4-037-008 | 玩家连续经营 | 可以理解余量、到期、评分与熟练，操作/疲劳由人工判定 | PENDING人工 |

## 参数与实现边界

- AI-044：复用pantry品类与冷藏天数；包装容量与单位显式配置，原先千分份金额体系不改。旧无批次档从载入当日起算保质期。
- AI-045：建议Perfect±100ms、Good±200ms，Good贡献85；逐拍平均代替整段清零，调度终点同步容差。轻微需求偏差容差与较缓惩罚外置，原Q/H/偏好分层保留。
- 自动操作基础85沿用AI-003建议，实际缺项、配料、物理状态仍改变最终菜品。手艺用模块制作分而不是顾客满意度，避免偏好影响成长。

## 已落地能力与文件

- `TDFoodStock`＋`content/markets/kitchen_stock.json`：批次、分类、包装、保质期；`TDShopSession`唯一数量账，FEFO、跨日损耗、子版本校验/迁移、按槽保存手艺。没有第二个库存/钱包Autoload。
- `TDGameProfile`装配工厂产品与商品信息，菜摊/远程采购/工厂交易均受同一采购资格约束。旧已付款供货仍兑现，正式配料ID接入原厂商生产线。
- `TDIngredientIcon`抽取原工厂图标并补齐当前食材，集市、冰箱和QTE复用；冰箱四类仅列非零库存，冷藏切配品保留属性和原到期日。
- `TDCookingQTE → TDCookingSession/Model → Shop`累计实耗接口；耗尽裁剪、禁用、反馈、结束核对不重扣，取消已倒料算消耗。订单预算排除已倒入的在途量。
- `CookingLane`复用同一切配、炒/蒸谱面和模型做自动；手艺门槛由Shop控制，QTE输入关闭但实际工序/热量/时间继续。画面显示当前自动工序，完成后手动端盘交付；暂停冻结。
- `cooking_system.json`、`service_content.json`外置宽松参数，CustomerScorer继续只读并只比较声明项。存档仍是原筹备/日结边界；没有新增营业中恢复机制。

## 测试替身与限制

- 新增自动测试的“历史四次100分”或“五次80分”字典只建立门槛前置条件，不能证明人类实际完成了这几次QTE。后续自动运行使用真实场景、BeatSheet、Controller、Model和库存；没有演示专用成品或固定满意度。
- 图形检查使用隔离存档和生成的键鼠事件，核对实际GPU渲染。实体键鼠手感、音画同步、连续营业疲劳和最终平衡仍PENDING。
- 旧档不凭历史客人分反推手艺，迁移后从0积累；无鲜度历史的存货从迁移日计期。果品暂未被可制作菜谱使用，因此对应分类可能为空。

## 复现与五步试玩

检查：`pwsh -NoProfile -File tools/check.ps1 -Suite stock`；真实厨房 `-Suite service`；正式多槽 `-Suite profiles`；全量/导出 `pwsh -NoProfile -File tools/export.ps1`。图形探针用锁定Godot运行 `--path F:/MyGameTBD --script res://tools/stock_visual_check.gd`，全部写artifacts，不能当真人试玩证据。

1. 新档进菜摊，确认主料为番茄/鸡蛋/米，其他调料按瓶/袋显示；解锁新菜后再检查供货范围。
2. 备料开门，去冰箱检查分类、图标、数量、剩余天数。切配后退回，日期应保持。
3. 手工做菜，M6观察按住时余量减少；将一包调料用尽后应变灰，提示已用完且点击不加料。
4. 合格手工成品会显示手艺增长，制作分>=80累计至400；装好锅料按F选自动，返回做另一锅，暂停/恢复后等成品再E端盘。
5. 打烊保存、重启继续，核对手艺与库存；跨越保质日期后在菜摊/账本核对过期损耗。记录自动耗时和宽松程度是否合适。

## 验证过程与保留证据

- `artifacts/check/stock-stream-final`：14/14（182断言），0失败/跳过，导入、加载、测试退出0；`stock-qte-final`：84/84（774断言），0失败/跳过/退出0。
- `artifacts/stock-visual-input.log`：实际Compatibility/NVIDIA GPU，8图，退出0；空调料真实点击不增加actual_actions，真实点击“自动制作”启动同一厨房流程。图片stock-market/factory/fridge/seasoning/empty-spice/automatic-choice/automatic-progress/kitchen-progress，已目视核对比例、文字和状态。
- 失败证据保留：stock-stream-1的会话身份测试前置错误、stock-profiles的批次数值类型往返差异（补显式整型规范化）、stock-kitchen-1的旧采购/冰箱断言、pre-export-20261025-135946的416/420。后者分别为旧150ms等待与新200ms窗不一致、两种旧档fixture/元数据断言、自动取消测试错误地试图营业中补货；均逐项修正，未放松生产门禁。
- 图形首轮自动未启动是探针未备齐调料，已改为另一个筹备期备好料的隔离槽；不修改营业中禁补货。保留stock-visual/stock-visual-final失败日志。
- 原料厂商/建筑核心、项目引擎锁、原始设计资料和真实玩家档未修改；远程CI本轮NOT_RUN。

## 最终交付（2026-10-25）

- 全量 `artifacts/check/pre-export-20261025-141250`：422/422，14426断言，573.026秒；导入、加载、测试退出0，0失败/0跳过。包含28项真实营业厨房、14项正式多槽/工厂往返，旧经济迁移字段全部保留。4条历史Float/Int比较提示不影响测试结果，未忽略解析/运行时错误。
- 导出 `artifacts/export/summary.json`：PASS，417运行资源，独立EXE启动和29项标题/存档/移动检查通过；新批次JSON、库存脚本和图标脚本已加入显式资源清单并审计。
- `build/TownDiner.exe` + 同目录`TownDiner.pck`为14:22生成的本地开发验证包。当前可玩内容是原经营流程加六项改进，未对外发布。
- AC-PHASE-4-037-001至007工程PASS；008与实体键鼠/音画及连续营业平衡PENDING。无新外部测试替身替代厨房联调；门槛历史成品字典仅为测试前置。
- 最后补强399分边界断言后 `artifacts/check/stock-boundary-final` 14/14再次通过；生产代码与全量/导出版本相同。
- 协作所有权：cook 12、economy 11、town-economy 1文件检查通过，24份角色文件与集成副本SHA256全部一致；集成者49文件检查通过，git diff --check退出0。保留工作树供审阅，不创建PR、不推送或合并。
- 当前切片工程就绪，停在试玩检查点。下一步收集上述五步试玩反馈，未自动推进其他Phase4任务。
